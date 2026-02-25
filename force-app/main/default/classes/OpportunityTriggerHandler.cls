/**
 * @description Trigger handler for Opportunity. Queues QuickBooks sync when Stage transitions to 'Paid'.
 * Pattern: One trigger per object; handler encapsulates logic. Bulkified and async for callouts.
 * Uses Queueable to avoid callouts in trigger context.
 * Invokes QB_OpportunityInvoiceSync via Queueable worker.
 */
public with sharing class OpportunityTriggerHandler {

    public static void afterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        List<Id> toSync = new List<Id>();

        for (Opportunity o : newList) {
            Opportunity oldO = oldMap != null ? oldMap.get(o.Id) : null;
            if (o.StageName == QB_Enums.STAGE_PAID && (oldO == null || oldO.StageName != QB_Enums.STAGE_PAID)) {
                toSync.add(o.Id);
            }
        }

        if (!toSync.isEmpty()) {
            System.enqueueJob(new QB_SyncQueueable(toSync));
        }
    }
}