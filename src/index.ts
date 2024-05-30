import {
    Context,
    createConnectorCustomizer,
    readConfig,
    logger,
    StdAccountUpdateInput,
    AttributeChangeOp
} from '@sailpoint/connector-sdk'
import {
    EntitlementRef,
    JsonPatchOperation,
    JsonPatchOperationOpEnum
} from 'sailpoint-api-client'
import { IscClient } from './isc-client'

// Connector customizer must be exported as module property named connectorCustomizer
export const connectorCustomizer = async () => {

    // Get connector source config
    const config = await readConfig()
    
    // Using SailPoint's TypeScript SDK to initialize the client
    const iscClient = new IscClient(config)

    return createConnectorCustomizer()
        .beforeStdAccountUpdate(async (context: Context, input: StdAccountUpdateInput) => {
            logger.info(input, `Running before account update for Access Profile ${input.identity}`)

            // Build an array of entitlements to remove based on the incoming plan
            let removedEntitlements: (string | undefined)[] = []
            for (const change of input.changes) {
                if (change.op === AttributeChangeOp.Remove) {
                    // Handle single or array values
                    if (Array.isArray(change.value)) {
                        removedEntitlements = [...removedEntitlements, ...change.value]
                    }
                    else {
                        removedEntitlements.push(change.value)
                    }
                }
            }

            // Get all current access profile entitlements
            const currentEntitlements = await iscClient.getAccessProfileEntitlementsById(input.identity)
            if (!currentEntitlements) {
                logger.error(input, `No current entitlements found for Access Profile ${input.identity}`)
                return input
            }

            // Build the new list of entitlements for an Access Profile (existing minus to be removed)
            const remainingEntitlements: EntitlementRef[] = []
            currentEntitlements.forEach(element => {
                if (!removedEntitlements.includes(element.id)) {
                    remainingEntitlements.push(element)
                }
            });

            // Create the new plan which will contain the exact JSON Patch body used by the connector operation
            const action: JsonPatchOperation[] = []
            // Access Profiles do not allow removing all entitlements
            // Change action to disable if all entitlements are to be removed
            if (!remainingEntitlements || remainingEntitlements.length === 0) {
                action.push({
                    op: JsonPatchOperationOpEnum.Replace,
                    path: '/enabled',
                    value: 'false'
                })
            }
            // Replace current entitlements with the new list of entitlements as the action otherwise
            else {
                action.push({
                    op: JsonPatchOperationOpEnum.Replace,
                    path: '/entitlements',
                    value: remainingEntitlements
                })
            }

            // Add action to the new plan
            const newInput: StdAccountUpdateInput = {
                ...input,
                changes: [{
                    op: AttributeChangeOp.Remove,
                    attribute: 'entitlements',
                    value: JSON.stringify(action)
                }]
            };

            // Return the input which will not be used anyway
            return newInput
        })
}