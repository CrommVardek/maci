#!/usr/bin/env node

import * as argparse from 'argparse' 
import { 
    calcBinaryTreeDepthFromMaxLeaves,
    calcQuinTreeDepthFromMaxLeaves,
} from './utils'

import {
    timeTravel,
    configureSubparser as configureSubparserForTimeTravel,
} from './timeTravel'

import {
    genMaciKeypair,
    configureSubparser as configureSubparserForGenMaciKeypair,
} from './genMaciKeypair'

import {
    genMaciPubkey,
    configureSubparser as configureSubparserForGenMaciPubkey,
} from './genMaciPubkey'

import {
    deployVkRegistry,
    configureSubparser as configureSubparserForDeployVkRegistry,
} from './deployVkRegistry'

import {
    setVerifyingKeys,
    configureSubparser as configureSubparserForSetVerifyingKeys,
} from './setVerifyingKeys'

import {
    create,
    configureSubparser as configureSubparserForCreate,
} from './create'

import {
    deployPoll,
    configureSubparser as configureSubparserForDeployPoll,
} from './deployPoll'

import {
    signup,
    configureSubparser as configureSubparserForSignup,
} from './signUp'

import {
    publish,
    configureSubparser as configureSubparserForPublish,
} from './publish'

import {
    processMessages,
    configureSubparser as configureSubparserForProcessMessages,
} from './process'

import {
    tally,
    configureSubparser as configureSubparserForTally,
} from './tally'

import {
    verify,
    configureSubparser as configureSubparserForVerify,
} from './verify'

const main = async () => {
    const parser = new argparse.ArgumentParser({ 
        description: 'Minimal Anti-Collusion Infrastructure',
    })

    const subparsers = parser.addSubparsers({
        title: 'Subcommands',
        dest: 'subcommand',
    })

    // Subcommand: timeTravel
    configureSubparserForTimeTravel(subparsers)

    // Subcommand: genMaciPubkey
    configureSubparserForGenMaciPubkey(subparsers)

    // Subcommand: genMaciKeypair
    configureSubparserForGenMaciKeypair(subparsers)

    // Subcommand: deployVkRegistry
    configureSubparserForDeployVkRegistry(subparsers)

    // Subcommand: setVerifyingKeys
    configureSubparserForSetVerifyingKeys(subparsers)

    // Subcommand: create
    configureSubparserForCreate(subparsers)

    // Subcommand: deployPoll
    configureSubparserForDeployPoll(subparsers)

    // Subcommand: signup
    configureSubparserForSignup(subparsers)

    // Subcommand: publish
    configureSubparserForPublish(subparsers)

    // Subcommand: process
    configureSubparserForProcessMessages(subparsers)

    // Subcommand: tally
    configureSubparserForTally(subparsers)

    // Subcommand: verify
    configureSubparserForVerify(subparsers)

    const args = parser.parseArgs()

    // Execute the subcommand method
    if (args.subcommand === 'timeTravel') {
        await timeTravel(args)
    } else if (args.subcommand === 'genMaciKeypair') {
        await genMaciKeypair(args)
    } else if (args.subcommand === 'genMaciPubkey') {
        await genMaciPubkey(args)
    } else if (args.subcommand === 'deployVkRegistry') {
        await deployVkRegistry(args)
    } else if (args.subcommand === 'setVerifyingKeys') {
        await setVerifyingKeys(args)
    } else if (args.subcommand === 'create') {
        await create(args)
    } else if (args.subcommand === 'deployPoll') {
        await deployPoll(args)
    } else if (args.subcommand === 'signup') {
        await signup(args)
    } else if (args.subcommand === 'publish') {
        await publish(args)
    } else if (args.subcommand === 'process') {
        await processMessages(args)
        // Force the process to exit as it might get stuck
        process.exit()
    } else if (args.subcommand === 'tally') {
        await tally(args)
        // Force the process to exit as it might get stuck
        process.exit()
    } else if (args.subcommand === 'verify') {
        await verify(args)
    }
}

if (require.main === module) {
    main()
}

export {
    processMessages,
    tally,
    calcBinaryTreeDepthFromMaxLeaves,
    calcQuinTreeDepthFromMaxLeaves,
}
