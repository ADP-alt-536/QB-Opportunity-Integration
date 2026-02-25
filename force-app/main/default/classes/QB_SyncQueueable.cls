/**
 * @description Queueable worker that invokes the invocable to sync Opportunities to QuickBooks.
 * Accepts a list of Opportunity Ids. Splits into chunks if needed. Safe for async callouts.
 * No DML/SOQL in loops beyond batched operations.
 */
public with sharing class QB_SyncQueueable implements Queueable, Database.AllowsCallouts {

    private final List<Id> opportunityIds;
    private final String defaultItemRef;

    public QB_SyncQueueable(List<Id> opportunityIds, String defaultItemRef) {
        this.opportunityIds = opportunityIds == null ? new List<Id>() : new List<Id>(opportunityIds);
        this.defaultItemRef = String.isBlank(defaultItemRef) ? '1' : defaultItemRef;
    }

    public QB_SyncQueueable(List<Id> opportunityIds) {
        this(opportunityIds, '1');
    }

    public void execute(QueueableContext qc) {
        if (opportunityIds.isEmpty()) return;

        final Integer CHUNK = 100;

        for (Integer i = 0; i < opportunityIds.size(); i += CHUNK) {
            List<Id> slice = opportunityIds.subList(i, Math.min(i + CHUNK, opportunityIds.size()));
            List<QB_OpportunityInvoiceSync.Input> inputs = new List<QB_OpportunityInvoiceSync.Input>();

            for (Id oppId : slice) {
                QB_OpportunityInvoiceSync.Input inRec = new QB_OpportunityInvoiceSync.Input();
                inRec.opportunityId = oppId;
                inRec.defaultItemRef = defaultItemRef;
                inputs.add(inRec);
            }

            QB_OpportunityInvoiceSync.sync(inputs);
        }
    }
}