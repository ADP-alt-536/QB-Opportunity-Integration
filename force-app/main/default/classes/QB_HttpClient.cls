/**
 * @description QuickBooks HTTP client using Named Credential for auth and base URL management
 * Follows governor limits best practices: bulk-safe, no DML/SOQL in loops; user-mode for DML called by services.
 * Uses enums from QB_Enums for constants.
 * Assumes a Named Credential named 'QuickBooks_NC' configured to target https://quickbooks.api.intuit.com with OAuth 2.0.
 * The QuickBooks company/realmId will be passed from calling service (from Account.QuickBooks_Company_Id__c or global config).
 * @author Agentforce
 */
public with sharing class QB_HttpClient {

    /**
     * @description Builds a fully-qualified QuickBooks API path for a given resource
     * @param realmId QuickBooks company id
     * @param resource e.g. 'customer' or 'invoice'
     * @return path like '/services/data/v3/company/{realmId}/{resource}'
     */
    private static String buildPath(String realmId, String resource) {
        if (String.isBlank(realmId)) {
            throw new QB_HttpException('Missing QuickBooks Company Id (realmId).');
        }
        // Named Credential base: https://quickbooks.api.intuit.com
        // QuickBooks v3 REST base: /v3/company/{realmId}/{resource}
        return QB_Enums.API_BASE + '/' + EncodingUtil.urlEncode(realmId, 'UTF-8') + '/' + resource;
    }

    /**
     * @description Performs a POST to the given resource with JSON payload
     */
    public static HttpResponse post(String realmId, String resource, String bodyJson) {
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('callout:' + QB_Enums.NAMED_CREDENTIAL + buildPath(realmId, resource));
        req.setHeader('Content-Type', QB_Enums.APPLICATION_JSON);
        req.setHeader('Accept', QB_Enums.APPLICATION_JSON);
        req.setBody(bodyJson);
        return send(req);
    }

    /**
     * @description Performs a GET to the given resource (optionally with query string already on resource)
     */
    public static HttpResponse get(String realmId, String resource) {
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:' + QB_Enums.NAMED_CREDENTIAL + buildPath(realmId, resource));
        req.setHeader('Accept', QB_Enums.APPLICATION_JSON);
        return send(req);
    }

    private static HttpResponse send(HttpRequest req) {
        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (System.CalloutException ex) {
            throw new QB_HttpException('Callout failed: ' + ex.getMessage(), ex);
        }
        Integer status = res.getStatusCode();
        if (status < 200 || status >= 300) {
            // Include response body snippet for diagnostics but avoid huge logs
            String body = res.getBody();
            if (body != null && body.length() > 2000) {
                body = body.substring(0, 2000) + '...';
            }
            throw new QB_HttpException('HTTP ' + status + ' - ' + res.getStatus() + ' Body: ' + body);
        }
        return res;
    }

    public class QB_HttpException extends Exception {}
}
