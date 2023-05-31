global with sharing class PromotionDeploymentToVersionCreate extends copado.AutomationConnector {
	
    private copado.PackageVersionCreateAction.Request request;
    private Map<Id, String> latestVersionByPackage = new Map<Id, String>();
    private Map<Id, copado__Artifact__c> packageById = new Map<Id, copado__Artifact__c>();
    private Map<Id, List<copado__User_Story__c>> userStoriesByPackage = new Map<Id, List<copado__User_Story__c>>();
    
    global override List<copado.AutomationConnector> getConnectors(copado.AutomationConnectorContext context) {
        this.latestVersionByPackage = new Map<Id, String>();
        this.packageById = new Map<Id, copado__Artifact__c>();
        this.userStoriesByPackage = new Map<Id, List<copado__User_Story__c>>();
        
        // Find pipeline from previous execution context and get the pipeline details to use later
        Id pipelineId = context.automationEvents[0].copado__Pipeline_Id__c;
        copado__Deployment_Flow__c pipeline = [SELECT Id, copado__Git_Repository__c FROM copado__Deployment_Flow__c WHERE Id = :pipelineId];
        
        // Get promotion ids from previous execution context and get the promotion details to use later
        Set<Id> promotionIds = getPromotionIdsFromData(context);
        List<copado__Promotion__c> promotions = [SELECT Id, copado__Source_Environment__c, copado__Destination_Environment__c FROM copado__Promotion__c WHERE Id IN :promotionIds];
        
        // Get pipeline connections details to use later
        if(!promotions.isEmpty()) {
            List<copado__Deployment_Flow_Step__c> pipelineConnections = [SELECT Id, copado__Source_Environment__c, copado__Destination_Environment__c, copado__Destination_Branch__c FROM copado__Deployment_Flow_Step__c WHERE copado__Deployment_Flow__c = :pipelineId];
            fillMapDataForPackages(promotions, pipelineConnections, pipeline);
        }
        return configureConnectors();
    }
    
    global override String executeAutomation() {
        return copado.PackageVersionCreateAction.create(new List<copado.PackageVersionCreateAction.Request>{ request })[0]?.job.Id;
    }
    
    global override String getAutomatedActionName() {
        return 'Package Version Create';
    }
    
    // PRIVATE

    private Set<Id> getPromotionIdsFromData(copado.AutomationConnectorContext context) {
        Set<Id> result = new Set<Id>();
        for (copado__Automation_Event__c event : context.automationEvents) {
            
            Response promotionDeployResponse = (Response) JSON.deserialize(
                event.copado__Action_Result__c,
                Response.class
            );

            copado__JobExecution__c jobExecution = promotionDeployResponse.jobExecution;

            ExecutionRequestData executionData = (ExecutionRequestData) JSON.deserialize(jobExecution.copado__DataJSON__c, ExecutionRequestData.class);
            if(executionData.deploymentDryRun==null || !executionData.deploymentDryRun) {
                result.add(executionData.promotionId);
            }
        }
        return result;
    }
    
    private void fillMapDataForPackages(List<copado__Promotion__c> promotions, List<copado__Deployment_Flow_Step__c> pipelineConnections, copado__Deployment_Flow__c pipeline) {
        Map<Id, List<copado__User_Story__c>> userStoriesByPromotionId = getUserStoriesByPromotionId(new Map<Id, copado__Promotion__c>(promotions).keySet());
        List<copado__Artifact__c> packages = getPackages(pipeline);
        Map<String, List<copado__Artifact__c>> packagesByBranch = getPackagesByBranch(packages);
        
        for(copado__Promotion__c promotion : promotions) {
            for(copado__Deployment_Flow_Step__c pipelineConnection : pipelineConnections) {
                if(promotion.copado__Source_Environment__c == pipelineConnection.copado__Source_Environment__c &&
                    promotion.copado__Destination_Environment__c == pipelineConnection.copado__Destination_Environment__c
                ) {
                    List<copado__Artifact__c> branchPackages = packagesByBranch.get(pipelineConnection.copado__Destination_Branch__c);
                    List<copado__User_Story__c> userStories = userStoriesByPromotionId.get(promotion.Id);
                    fillData(branchPackages, userStories);
                }
            }
        }
    }
    
    private Map<Id, List<copado__User_Story__c>> getUserStoriesByPromotionId(Set<Id> promotionIds) {
        Map<Id, List<copado__User_Story__c>> result = new Map<Id, List<copado__User_Story__c>>();
		Set<Id> userStoryIds = new Set<Id>();
        List<copado__Promoted_User_Story__c> promotedUserStories = [SELECT Id, copado__User_Story__c, copado__Promotion__c 
                                                                    FROM copado__Promoted_User_Story__c 
                                                                    WHERE copado__Promotion__c IN :promotionIds];
        
        for (copado__Promoted_User_Story__c promotedUserStory : promotedUserStories) {
            userStoryIds.add(promotedUserStory.copado__User_Story__c);
        }

        Map<Id, copado__User_Story__c> userStoryById = new Map<Id, copado__User_Story__c>([SELECT Id, copado__Release__c, copado__Release__r.copado__Version__c
                                                                                           , copado__Release__r.Name
                                                                                           FROM copado__User_Story__c 
                                                                                           WHERE Id IN :userStoryIds]);

        for (copado__Promoted_User_Story__c promotedUserStory : promotedUserStories) {
            if(!result.containsKey(promotedUserStory.copado__Promotion__c)) {
                result.put(promotedUserStory.copado__Promotion__c, new List<copado__User_Story__c>());
            }
            result.get(promotedUserStory.copado__Promotion__c).add(userStoryById.get(promotedUserStory.copado__User_Story__c));
        }

        return result;
    }
    
    private List<copado__Artifact__c> getPackages(copado__Deployment_Flow__c pipeline) {
        return [
            SELECT Id,
                copado__Artifact_Version__c,
                copado__Artifact_Version__r.copado__Version_number__c,
                copado__Description__c,
                copado__DefaultBranch__c,
                copado__DefaultPath__c
            FROM copado__Artifact__c
            WHERE copado__Pipeline__c = :pipeline.Id
                AND copado__Artifact_Repository__c = :pipeline.copado__Git_Repository__c
            WITH SECURITY_ENFORCED
        ];
    }
    
    private Map<String, List<copado__Artifact__c>> getPackagesByBranch(List<copado__Artifact__c> packages) {
        Map<String, List<copado__Artifact__c>> result = new Map<String, List<copado__Artifact__c>>();
        
        for(copado__Artifact__c aPackage : packages) {
            if(!result.containsKey(aPackage.copado__DefaultBranch__c)) {
                result.put(aPackage.copado__DefaultBranch__c, new List<copado__Artifact__c>());
            }
            result.get(aPackage.copado__DefaultBranch__c).add(aPackage);
        }
        
        return result;
    }

    private void fillData(List<copado__Artifact__c> branchPackages, List<copado__User_Story__c> userStories) {
        branchPackages = branchPackages == null ? new List<copado__Artifact__c>() : branchPackages;
        for(copado__Artifact__c aPackage : branchPackages) {
            if(!userStoriesByPackage.containsKey(aPackage.Id)) {
                userStoriesByPackage.put(aPackage.Id, new List<copado__User_Story__c>());
                latestVersionByPackage.put(aPackage.Id, aPackage.copado__Artifact_Version__r?.copado__Version_number__c);
                packageById.put(aPackage.Id, aPackage);
            }
            userStoriesByPackage.get(aPackage.Id).addAll(userStories);
        }
    }
    
    private List<copado.AutomationConnector> configureConnectors() {
        List<copado.AutomationConnector> result = new List<copado.AutomationConnector>();
        Map<Id, PackageVersion> newVersionByPackage = getNewVersionByPackage();
        
        Map<Id, copado__Artifact_Version__c> packageId2packageVersion = new Map<Id, copado__Artifact_Version__c>();
        for (Id packageId : newVersionByPackage.keySet()) {
            copado__Artifact_Version__c packageVersion = new copado__Artifact_Version__c(copado__Artifact__c = packageId, cmcSf__Code_Coverage__c = true);
            if (newVersionByPackage.get(packageId).releaseID != null)
            {
                packageVersion.copado__Release__c = newVersionByPackage.get(packageId).releaseID;
                packageVersion.copado__Version_Name__c = newVersionByPackage.get(packageId).name;
            }
            packageId2packageVersion.put(packageId, packageVersion);
        }
        insert packageId2packageVersion.values();

        for (Id packageId : newVersionByPackage.keySet()) {
            PackageVersion packageVersion = newVersionByPackage.get(packageId);

            VersionJSONParameters jsonInformation = new VersionJSONParameters();
            jsonInformation.branch = packageById.get(packageId).copado__DefaultBranch__c;
            jsonInformation.path = packageById.get(packageId).copado__DefaultPath__c;
            jsonInformation.codecoverage = true;
            jsonInformation.skipvalidation = false;
            jsonInformation.installationkeybypass = true;
            if(packageVersion != null && packageVersion.versionNumber != null){
                jsonInformation.tag = packageVersion.versionNumber;
            }
            jsonInformation.versionId = packageId2packageVersion.get(packageId).Id;

             //Change to set the context ID for the package version id instead of package
            copado.PackageVersionCreateAction.Request request = new copado.PackageVersionCreateAction.Request(packageId, JSON.serialize(jsonInformation));
            if(packageVersion != null && packageVersion.versionNumber != null){
                request.versionName = packageVersion.name;
                request.versionNumber = packageVersion.versionNumber;
            }
            
            request.description = packageById.get(packageId).copado__Description__c;

            PromotionDeploymentToVersionCreate connector = new PromotionDeploymentToVersionCreate();
            connector.request = request;
            connector.context = context;
            result.add(connector);
        }
        return result;
    }
    
    private Map<Id, PackageVersion> getNewVersionByPackage() {
        Map<Id, PackageVersion> result = new Map<Id, PackageVersion>();
        for (Id packageId : userStoriesByPackage.keySet()) {
            List<copado__User_Story__c> userStories = userStoriesByPackage.get(packageId);
            Set<PackageVersion> versions = new Set<PackageVersion>();
            for (copado__User_Story__c userStory : userStories) {
                if (userStory.copado__Release__c != null && userStory.copado__Release__r.copado__Version__c != null) {
                    PackageVersion version = new PackageVersion();
                    version.name = userStory.copado__Release__r.Name;
                    version.versionNumber = userStory.copado__Release__r.copado__Version__c;
                    version.releaseId = userStory.copado__Release__c;
                    versions.add(version);
                }
            }
            List<PackageVersion> versionList = new List<PackageVersion>(versions);
            if (versionList.isEmpty()) {
                result.put(packageId, calculateVersionFromExistingOnes(packageId));
            } else {
                if (versionList.size() == 1) {
                    result.put(packageId, versionList[0]);
                } else {
                    versionList.sort();
                    result.put(packageId, versionList[versionList.size() - 1]);
                }
            }
        }
        return result;
    }
    
    private PackageVersion calculateVersionFromExistingOnes(Id packageId) {
        PackageVersion result = new PackageVersion();
        String currentVersion = latestVersionByPackage.get(packageId);
        if(String.isNotBlank(currentVersion)) {
            List<String> versionPieces = currentVersion.split('\\.');
            if(!versionPieces.isEmpty()) {
                Integer newBuild = Integer.valueOf(versionPieces[versionPieces.size() - 1]) + 1;
                versionPieces[versionPieces.size() - 1] = String.valueOf(newBuild);
                result.versionNumber = String.join(versionPieces, '.');
            }
        }
        return result;
    } 
    
    // WRAPPER
    
    public class PackageVersion {
        public String name;
        public String versionNumber;
        public Id releaseId;
    }

    public class VersionJSONParameters {
        public String branch;
        public String path;
        public Boolean installationkeybypass;
        public Boolean codecoverage;
        public Boolean skipvalidation;
        public String tag;
        public String versionId;
    }

    private class ExecutionRequestData {
        private String promotionId;
        private Boolean deploymentDryRun;
    }
    
    public class Response {
        public copado__JobExecution__c jobExecution;
    }
}