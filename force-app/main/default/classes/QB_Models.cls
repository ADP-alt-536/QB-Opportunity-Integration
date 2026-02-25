public with sharing class QB_Models {

    // Customer Upsert Request
    public class CustomerUpsertReq {
        public String DisplayName;
        public String PrimaryEmailAddr;
        public BillingAddress BillAddr;
    }

    // Customer Billing Address
    public class BillingAddress {
        public String Line1;
        public String City;
        public String State;
        public String PostalCode;
        public String Country;
    }

    // Customer Response
    public class CreatedCustomerRes {
        public Customer Customer;
    }

    public class Customer {
        public String Id;
        public String DisplayName;
    }

    // Invoice Request
    public class InvoiceCreateReq {
        public List<InvoiceLine> Line;
    }

    public class InvoiceLine {
        public SalesItemLineDetail SalesItemLineDetail;
    }

    public class SalesItemLineDetail {
        public String ItemRef;
        public Decimal Amount;
    }

    // Invoice Response
    public class CreatedInvoiceRes {
        public Invoice Invoice;
    }

    public class Invoice {
        public String Id;
        public Decimal TotalAmt;
    }
}