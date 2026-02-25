/**
 * @description Enums and constants for QuickBooks integration
 * @author Agentforce
 */
public with sharing class QB_Enums {
    public enum InvoiceStatus {
        OPEN, PAID, VOID
    }
    public enum HttpMethod {
        GET, POST, PUT, DELETE_METHOD, PATCH
    }
    public enum ContentType {
        JSON, FORM_URL_ENCODED
    }

    public static final String NAMED_CREDENTIAL = 'QuickBooks_NC';
    public static final String API_BASE = '/v3/company';
    public static final String INVOICE_RESOURCE = 'invoice';
    public static final String CUSTOMER_RESOURCE = 'customer';
    public static final String APPLICATION_JSON = 'application/json';

    public static final String STAGE_PAID = 'Paid';
}
