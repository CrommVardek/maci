include "./messageHasher.circom"
include "./messageValidator.circom"
include "./messageToCommand.circom"
include "./privToPubKey.circom"
include "./trees/incrementalQuinTree.circom";
include "../node_modules/circomlib/circuits/mux1.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

template ProcessMessages(
    stateTreeDepth,
    msgTreeDepth,
    msgSubTreeDepth,
    voteOptionTreeDepth
) {

    // stateTreeDepth: the depth of the state tree
    // msgTreeDepth: the depth of the message tree
    // msgSubTreeDepth: the depth of the shortest tree that can fit all the
    //                  messages
    // voteOptionTreeDepth: depth of the vote option tree

    var MSG_LENGTH = 8; // iv and data
    var BALLOT_LENGTH = 2;
    var TREE_ARITY = 5;
    var batchSize = TREE_ARITY ** msgSubTreeDepth;
    var PACKED_CMD_LENGTH = 4;

    var BALLOT_NONCE_IDX = 0;
    var BALLOT_VO_ROOT_IDX = 1;

    var STATE_LEAF_PUB_X_IDX = 0;
    var STATE_LEAF_PUB_Y_IDX = 1;
    var STATE_LEAF_VOICE_CREDIT_BALANCE_IDX = 2;
    
    // CONSIDER: sha256 hash any values from the contract, pass in the hash
    // as a public input, and pass in said values as private inputs. This saves
    // a lot of gas for the verifier at the cost of constraints for the prover.

    //  ----------------------------------------------------------------------- 
    //      0. Ensure that the maximum vote options signal is valid and whether
    //      the maximum users signal is valid
    signal input maxVoteOptions;
    component maxVoValid = LessEqThan(32);
    maxVoValid.in[0] <== maxVoteOptions;
    maxVoValid.in[1] <== TREE_ARITY ** voteOptionTreeDepth;
    maxVoValid.out === 1;

    signal input maxUsers;
    component maxUsersValid = LessEqThan(32);
    maxUsersValid.in[0] <== maxUsers;
    maxUsersValid.in[1] <== TREE_ARITY ** stateTreeDepth;
    maxUsersValid.out === 1;

    //  ----------------------------------------------------------------------- 
    //      1. Check whether each message exists in the message tree. Throw if
    //         otherwise (aka create a constraint that prevents such a proof).

    //  To save constraints, compute the subroot of the messages and check
    //  whether the subroot is a member of the message tree. This means that
    //  batchSize must be the message tree arity raised to some power
    // (e.g. 5 ^ n)

    // The existing message root
    signal input msgRoot;
    // The messages
    signal private input msgs[batchSize][MSG_LENGTH];
    // The message Merkle proofs
    signal input msgSubrootPathElements[msgTreeDepth - msgSubTreeDepth][TREE_ARITY - 1];

    // The index of the first message leaf in the batch, inclusive. Note that
    // messages are processed in reverse order, so this is not be the index of
    // the first message to process (unless there is only 1 message)
    signal input batchStartIndex;

    // The index of the last message leaf in the batch to process, exclusive.
    // This value may be less than batchStartIndex + batchSize if this batch is
    // the last batch and the total number of mesages is not a multiple of the
    // batch size.
    signal input batchEndIndex;

    signal input msgTreeZeroValue;
    component msgBatchLeavesExists = QuinBatchLeavesExists(msgTreeDepth, msgSubTreeDepth);
    msgBatchLeavesExists.root <== msgRoot;

    // Hash each Message so we can check its existence in the Message tree
    // later
    component messageHashers[batchSize];
    for (var i = 0; i < batchSize; i ++) {
        messageHashers[i] = MessageHasher();
        for (var j = 0; j < MSG_LENGTH; j ++) {
            messageHashers[i].in[j] <== msgs[i][j];
        }
    }

    // If batchEndIndex - batchStartIndex < batchSize, the remaining
    // message hashes should be the zero value.
    // e.g. [m, z, z, z, z] if there is only 1 real message in the batch
    // This allows us to have a batch of messages which is only partially
    // full.
    component lt[batchSize];
    component muxes[batchSize];

    for (var i = 0; i < batchSize; i ++) {
        lt[i] = LessEqThan(32);
        lt[i].in[0] <== batchStartIndex + i;
        lt[i].in[1] <== batchEndIndex;

        muxes[i] = Mux1();
        muxes[i].s <== lt[i].out;
        muxes[i].c[0] <== msgTreeZeroValue;
        muxes[i].c[1] <== messageHashers[i].hash;
        msgBatchLeavesExists.leaves[i] <== muxes[i].out;
    }

    for (var i = 0; i < msgTreeDepth - msgSubTreeDepth; i ++) {
        for (var j = 0; j < TREE_ARITY - 1; j ++) {
            msgBatchLeavesExists.path_elements[i][j] <== msgSubrootPathElements[i][j];
        }
    }

    // Assign values to msgBatchLeavesExists.path_index. Since
    // msgBatchLeavesExists tests for the existence of a subroot, the length of
    // the proof is the last n elements of a proof from the root to a leaf
    // where n = msgTreeDepth - msgSubTreeDepth
    // e.g. if batchStartIndex = 25, msgTreeDepth = 4, msgSubtreeDepth = 2
    // msgBatchLeavesExists.path_index should be:
    // [1, 0]
    component msgBatchPathIndices = QuinGeneratePathIndices(msgTreeDepth);
    msgBatchPathIndices.in <== batchStartIndex;
    for (var i = msgSubTreeDepth; i < msgTreeDepth; i ++) {
        msgBatchLeavesExists.path_index[i - msgSubTreeDepth] <== msgBatchPathIndices.out[i];
    }

    //  ----------------------------------------------------------------------- 
    //     2. Decrypt each Message to a Command

    // MessageToCommand derives the ECDH shared key from the coordinator's
    // private key and the message's ephemeral public key. Next, it uses this
    // shared key to decrypt a Message to a Command.

    // The coordinator's public key
    signal private input coordPrivKey;

    // The cooordinator's public key from the contract.
    signal input coordPubKey[2];

    // The ECDH public key per message
    signal input encPubKeys[batchSize][2];

    // Ensure that the coordinator's public key from the contract is correct
    // based on the given private key - that is, the prover knows the
    // coordinator's private key.
    component derivedPubKey = PrivToPubKey();
    derivedPubKey.privKey <== coordPrivKey;
    derivedPubKey.pubKey[0] === coordPubKey[0];
    derivedPubKey.pubKey[1] === coordPubKey[1];

    // Decrypt each Message into a Command
    component commands[batchSize];
    for (var i = 0; i < batchSize; i ++) {
        commands[i] = MessageToCommand();
        commands[i].encPrivKey <== coordPrivKey;
        commands[i].encPubKey[0] <== encPubKeys[i][0];
        commands[i].encPubKey[1] <== encPubKeys[i][1];
        for (var j = 0; j < MSG_LENGTH; j ++) {
            commands[i].message[j] <== msgs[i][j];
        }
    }

    //  ----------------------------------------------------------------------- 
    //    3. Check that each state leaf is in the current state tree

    var STATE_LEAF_LENGTH = 3;
    signal input currentStateRoot;

    // The existing state root
    signal private input currentStateLeaves[batchSize][STATE_LEAF_LENGTH];
    signal private input currentStateLeavesPathElements[batchSize][stateTreeDepth][TREE_ARITY - 1];

    // Hash each original state leaf
    component currentStateLeafHashers[batchSize];
    for (var i = 0; i < batchSize; i++) {
        currentStateLeafHashers[i] = Hasher3();
        for (var j = 0; j < STATE_LEAF_LENGTH; j++) {
            currentStateLeafHashers[i].in[j] <== currentStateLeaves[i][j];
        }
    }

    component currentStateLeavesPathIndices[batchSize];
    for (var i = 0; i < batchSize; i ++) {
        currentStateLeavesPathIndices[i] = QuinGeneratePathIndices(stateTreeDepth);
        currentStateLeavesPathIndices[i].in <== commands[i].stateIndex;
    }

    // For each Command (a decrypted Message), prove knowledge of the state
    // leaf and its membership in the current state root.
    component currentStateLeavesQle[batchSize];
    for (var i = 0; i < batchSize; i ++) {
        currentStateLeavesQle[i] = QuinLeafExists(stateTreeDepth);
        currentStateLeavesQle[i].root <== currentStateRoot;
        currentStateLeavesQle[i].leaf <== currentStateLeafHashers[i].hash;
        for (var j = 0; j < stateTreeDepth; j ++) {
            currentStateLeavesQle[i].path_index[j] <== currentStateLeavesPathIndices[i].out[j];
            for (var k = 0; k < TREE_ARITY - 1; k++) {
                currentStateLeavesQle[i].path_elements[j][k] <== currentStateLeavesPathElements[i][j][k];
            }
        }
    }

    //  ----------------------------------------------------------------------- 
    //    4. Check whether each ballot exists in the original ballot tree
    
    // The existing ballot root
    signal input currentBallotRoot
    signal private input currentBallots[batchSize][BALLOT_LENGTH];
    signal private input currentBallotsPathElements[batchSize][stateTreeDepth][TREE_ARITY - 1];

    component currentBallotsHashers[batchSize];

    component currentBallotsQle[batchSize];
    for (var i = 0; i < batchSize; i ++) {
        currentBallotsHashers[i] = HashLeftRight();
        currentBallotsHashers[i].left <== currentBallots[i][BALLOT_NONCE_IDX];
        currentBallotsHashers[i].right <== currentBallots[i][BALLOT_VO_ROOT_IDX];

        currentBallotsQle[i] = QuinLeafExists(stateTreeDepth);
        currentBallotsQle[i].root <== currentBallotRoot;
        currentBallotsQle[i].leaf <== currentBallotsHashers[i].hash;
        for (var j = 0; j < stateTreeDepth; j ++) {
            currentBallotsQle[i].path_index[j] <== currentStateLeavesPathIndices[i].out[j];
            for (var k = 0; k < TREE_ARITY - 1; k++) {
                currentBallotsQle[i].path_elements[j][k] <== currentBallotsPathElements[i][j][k];
            }
        }
    }

    //  ----------------------------------------------------------------------- 
    //    5. Check whether the existing vote weight exists in the vote option
    //    tree of the ballot
    signal private input currentVoteWeights[batchSize];
    signal private input currentVoteWeightsPathElements[batchSize][voteOptionTreeDepth][TREE_ARITY - 1];
    component currentVoteWeightsQle[batchSize];
    component currentVoteWeightsPathIndices[batchSize];
    for (var i = 0; i < batchSize; i ++) {

        currentVoteWeightsPathIndices[i] = QuinGeneratePathIndices(voteOptionTreeDepth);
        currentVoteWeightsPathIndices[i].in <== commands[i].voteOptionIndex;

        currentVoteWeightsQle[i] = QuinLeafExists(voteOptionTreeDepth);
        currentVoteWeightsQle[i].root <== currentBallots[i][BALLOT_VO_ROOT_IDX];
        currentVoteWeightsQle[i].leaf <== currentVoteWeights[i];
        for (var j = 0; j < voteOptionTreeDepth; j ++) {
            currentVoteWeightsQle[i].path_index[j] <== currentVoteWeightsPathIndices[i].out[j];
            for (var k = 0; k < TREE_ARITY - 1; k++) {
                currentVoteWeightsQle[i].path_elements[j][k] <== currentVoteWeightsPathElements[i][j][k];
            }
        }
    }

    //  ----------------------------------------------------------------------- 
    // 5. Check whether each message is valid or not
    // This entails the following checks:
    //     a) Whether the max state tree index is correct
    //     b) Whether the max vote option tree index is correct
    //     c) Whether the nonce is correct
    //     d) Whether the signature is correct
    //     e) Whether there are sufficient voice credits
    component messageValid[batchSize];
    for (var i = 0; i < batchSize; i ++) {
        messageValid[i] = MessageValidator();
        messageValid[i].stateTreeIndex <== commands[i].stateIndex;
        messageValid[i].maxUsers <== maxUsers;
        messageValid[i].voteOptionIndex <== commands[i].voteOptionIndex;
        messageValid[i].maxVoteOptions <== maxVoteOptions;
        messageValid[i].originalNonce <== currentBallots[i][BALLOT_NONCE_IDX];
        messageValid[i].nonce <== commands[i].nonce;
        messageValid[i].pubKey[0] <== currentStateLeaves[i][STATE_LEAF_PUB_X_IDX];
        messageValid[i].pubKey[1] <== currentStateLeaves[i][STATE_LEAF_PUB_Y_IDX];
        messageValid[i].sigR8[0] <== commands[i].sigR8[0];
        messageValid[i].sigR8[1] <== commands[i].sigR8[1];
        messageValid[i].sigS <== commands[i].sigS;
        messageValid[i].currentVoiceCreditBalance <== currentStateLeaves[i][STATE_LEAF_VOICE_CREDIT_BALANCE_IDX];
        messageValid[i].currentVotesForOption <== currentVoteWeights[i];
        messageValid[i].voteWeight <== commands[i].newVoteWeight;

        for (var j = 0; j < PACKED_CMD_LENGTH; j++) {
            messageValid[i].cmd[j] <== commands[i].packedCommandOut[j];
        }
    }

    //  ----------------------------------------------------------------------- 
    // 6. For each message, corresponding state leaf, and new state root,
    // create an updated state leaf and prove that it belongs to the new state
    // root. The updated state leaf and root should be the same if the message
    // is invalid.

    // The new state tree root
    /*signal input newStateRoot;*/
    /*signal input newStateLeavesPathElements[];*/
    /*signal private input currentVoteWeightsPathElements[batchSize][voteOptionTreeDepth][TREE_ARITY - 1];*/

    //  ----------------------------------------------------------------------- 
    // 7. For each message and corresponding ballot leaf, create an updated
    // ballot leaf and ballot root. The updated ballot leaf and root should be
    // the same if the message is invalid.

    //  ----------------------------------------------------------------------- 
    // 8. Prove that the random state leaf belongs in the final state root
    // signal private input randomStateLeafHash;

    //  ----------------------------------------------------------------------- 
    // 9. Prove that the random ballot leaf belongs in the final ballot root
    // signal private input randomBallotLeafHash;

    // The new ballot root
    /*signal output newBallotRoot;*/
}