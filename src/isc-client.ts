import { logger } from '@sailpoint/connector-sdk'
import axiosRetry from 'axios-retry'
import {
    AccessProfile,
    AccessProfilesApi,
    Configuration,
    ConfigurationParameters,
    EntitlementRef,
    JsonPatchOperation
} from 'sailpoint-api-client'

export class IscClient {

    private readonly config: any
    private readonly apiConfig: Configuration

    constructor(config: any) {
        this.config = config
        this.apiConfig = this.createApiConfig()
    }

    // Configure the SailPoint SDK API Client
    createApiConfig() {
        const ConfigurationParameters: ConfigurationParameters = {
            baseurl: this.config.genericWebServiceBaseUrl,
            clientId: this.config.client_id,
            clientSecret: this.config.client_secret,
            tokenUrl: this.config.token_url
        }
        const apiConfig = new Configuration(ConfigurationParameters)
        apiConfig.retriesConfig = {
            retries: 10,
            retryDelay: (retryCount, error) => axiosRetry.exponentialDelay(retryCount, error, 2000),
            retryCondition: (error) => {
                return error.response?.status === 429;
            },
            onRetry: (retryCount, error, requestConfig) => {
                logger.debug(`Retrying API [${requestConfig.url}] due to request error: [${error}]. Try number [${retryCount}]`)
            }
        }
        return apiConfig
    }

    async getAccessProfileEntitlementsById(id: string): Promise<EntitlementRef[] | undefined> {
        const accessProfilesApi = new AccessProfilesApi(this.apiConfig)
        try {
            const accessProfile = await accessProfilesApi.getAccessProfile({ id: id })
            // Check if no access profiles exists
            if (!accessProfile.data.entitlements) {
                return
            } else {
                return accessProfile.data.entitlements
            }
        } catch (error) {
            let errorMessage = `Error listing Access Profiles by filter using Access Profiles API ${error instanceof Error ? error.message : error}`
            logger.error(errorMessage)
            logger.debug(error, 'Failed Access Profiles API request')
            return
        }
    }
    async patchAccessProfile(id: string, action: JsonPatchOperation[]): Promise<AccessProfile | undefined> {
        const accessProfilesApi = new AccessProfilesApi(this.apiConfig)
        try {
            const accessProfile = await accessProfilesApi.patchAccessProfile({ id: id, jsonPatchOperation: action })
            // Check if no access profiles exists
            return accessProfile.data
        } catch (error) {
            let errorMessage = `Error listing Access Profiles by filter using Access Profiles API ${error instanceof Error ? error.message : error}`
            logger.error(errorMessage)
            logger.debug(error, 'Failed Access Profiles API request')
            return
        }
    }
}