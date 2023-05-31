@IsTest
private class PromotionDeploymentToVersionCreateTest {

    @TestSetup 
    private static void setupData() {
        User stdUser = createUserWithPermissionSet();
        System.runAs(stdUser) {
            enableCopadoLicenses(stdUser);
            createData();
        }
    }

    @IsTest
    private static void connectAndExecute() {
        System.runAs(getRunAsUser()) {
            // Setup
            copado__Promotion__c firstPromotion = [SELECT Id FROM copado__Promotion__c ORDER BY CreatedDate LIMIT 1];
            copado__JobExecution__c jobExecutionRecord = new copado__JobExecution__c(
                copado__DataJson__c = '{ "promotionId" : "' + firstPromotion.Id + '"}'
            );
            insert jobExecutionRecord;
            
            copado__Deployment_Flow__c pipeline = [SELECT Id FROM copado__Deployment_Flow__c LIMIT 1];
                       
            Response response = new Response();
            response.jobExecution = jobExecutionRecord;
            
            System.debug('jobExecutionRecord:' + jobExecutionRecord);
            System.debug('JSON.serialize(response):' + JSON.serialize(response));

            copado__Automation_Event__c event = new copado__Automation_Event__c(
                copado__Pipeline_Id__c = pipeline.Id,
                copado__Action_Name__c = 'PromotionDeployment',
                copado__Action_Status__c = 'Successful',
                copado__Action_Result__c = JSON.serialize(response)
            );
            insert event;
            
            // Exercise
            Test.startTest();
            PromotionDeploymentToVersionCreate versionCreateConnector = new PromotionDeploymentToVersionCreate();
            copado.AutomationConnectorContext context = new copado.AutomationConnectorContext();
            context.automationEvents = new List<copado__Automation_Event__c>{ event };
            versionCreateConnector.context = context;
            List<copado.AutomationConnector> connectors = (List<copado.AutomationConnector>) versionCreateConnector.getConnectors(context);
            System.assertEquals(1, connectors.size(), 'Exactly one connector should be created');
            connectors[0].executeAutomation();
            Test.stopTest();
            
            // Verify
            copado__JobExecution__c jobExecutionId = [SELECT Id, copado__DataJson__c 
                                 FROM copado__JobExecution__c 
                                 ORDER BY CreatedDate DESC LIMIT 1];
            System.assertNotEquals(
                jobExecutionRecord.Id,
                jobExecutionId.Id,
                'A new package version create job execution is started'
            );
            
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(jobExecutionId.copado__DataJson__c);
            Map<String, Object> inf = (Map<String, Object>) JSON.deserializeUntyped(m.get('jsonInformation').toString());
            String versionID = inf.get('versionId').toString();
            copado__Artifact_Version__c artifactVersion = [SELECT Id, copado__version__c, copado__release__c
                                                           FROM copado__Artifact_Version__c 
                                                           WHERE ID = :versionID];
            system.assertNotEquals(null, artifactVersion);
            system.assertNotEquals(null, artifactVersion.copado__release__c);
            system.assertEquals('1.1.1', artifactVersion.copado__version__c);
        }
    }

    @IsTest
    private static void ignorePromotionValidations() {
        System.runAs(getRunAsUser()) {
            // Setup
            copado__Promotion__c firstPromotion = [SELECT Id FROM copado__Promotion__c ORDER BY CreatedDate LIMIT 1];
            copado__JobExecution__c jobExecutionRecord = new copado__JobExecution__c(
                copado__DataJson__c = '{ "promotionId" : "' + firstPromotion.Id + '", "deploymentDryRun": true}'
            );
            insert jobExecutionRecord;
            
            copado__Deployment_Flow__c pipeline = [SELECT Id FROM copado__Deployment_Flow__c LIMIT 1];
            
            Response response = new Response();
            response.jobExecution = jobExecutionRecord;

            copado__Automation_Event__c event = new copado__Automation_Event__c(
                copado__Pipeline_Id__c = pipeline.Id,
                copado__Action_Name__c = 'PromotionDeployment',
                copado__Action_Status__c = 'Successful',
                copado__Action_Result__c = JSON.serialize(response)
            );
            insert event;
            
            // Exercise
            Test.startTest();
            PromotionDeploymentToVersionCreate versionCreateConnector = new PromotionDeploymentToVersionCreate();
            copado.AutomationConnectorContext context = new copado.AutomationConnectorContext();
            context.automationEvents = new List<copado__Automation_Event__c>{ event };
            versionCreateConnector.context = context;
            List<copado.AutomationConnector> connectors = (List<copado.AutomationConnector>) versionCreateConnector.getConnectors(context);
            System.assertEquals(0, connectors.size(), 'No connector should be gathered for a Validation Promotion');
            Test.stopTest();
        }
    }

    // DATA CREATION & HELPERS

    private static void createData() {
        copado__JobTemplate__c jobTemplate = new copado__JobTemplate__c(
            Name = 'CreatePackageVersion',
            copado__Version__c = 1);
        insert jobTemplate;

        copado__JobStep__c jobStep = new copado__JobStep__c(
            Name = 'Step 1',
            copado__Type__c = 'Flow',
            copado__ConfigJson__c = '{"flowName" : "MockedFlow"}',
            copado__JobTemplate__c = jobTemplate.Id);
        insert jobStep;
        
        List<copado__Environment__c> environments = new List<copado__Environment__c>();
        copado__Environment__c dev1Env = new copado__Environment__c(
            Name = 'dev1',
            copado__Type__c = 'Sandbox',
            copado__Platform__c = 'Other');
        environments.add(dev1Env);
        copado__Environment__c dev2Env = new copado__Environment__c(
            Name = 'dev2',
            copado__Type__c = 'Sandbox',
            copado__Platform__c = 'Other');
        environments.add(dev2Env);
        copado__Environment__c intEnv = new copado__Environment__c(
            Name = 'int',
            copado__Type__c = 'Sandbox',
            copado__Platform__c = 'Other');
        environments.add(intEnv);
        copado__Environment__c uatEnv = new copado__Environment__c(
            Name = 'uat',
            copado__Type__c = 'Sandbox',
            copado__Platform__c = 'Other');
        environments.add(uatEnv);
        copado__Environment__c prodEnv = new copado__Environment__c(
            Name = 'prod',
            copado__Type__c = 'Sandbox',
            copado__Platform__c = 'Other');
        environments.add(prodEnv);
        copado__Environment__c devHubEnv = new copado__Environment__c(
            Name = 'devHub',
            copado__Type__c = 'Production/Developer',
            copado__Platform__c = 'Other');
        environments.add(devHubEnv);
        insert environments;
        
        copado__Org__c devHubOrg = [
            SELECT Id, Name, copado__Environment__c, copado__Platform__c, copado__Oauth_Signature__c, copado__Validated_Date__c, copado__Disable_Validation__c, copado__SFDC_Org_ID__c, copado__is_Developer_Hub_Org__c
            FROM copado__Org__c
            WHERE copado__Platform__c = 'Other' AND Name = :'devHub'
        ];
        devHubOrg.copado__Username__c = UserInfo.getUserName();
        devHubOrg.copado__SFDC_Org_ID__c = UserInfo.getOrganizationId() + '_' + UserInfo.getUserId();
        devHubOrg.copado__Oauth_Signature__c = devHubOrg.Name;
        devHubOrg.copado__Validated_Date__c = System.now();
        devHubOrg.copado__Disable_Validation__c = true;
        devHubOrg.copado__is_Developer_Hub_Org__c = true;
        update devHubOrg;

        copado__Git_Repository__c repo = new copado__Git_Repository__c(Name = 'Test Repo');
        insert repo;

        copado__Deployment_Flow__c pipeline = new copado__Deployment_Flow__c(
            Name = 'Test Pipeline',
            copado__Active__c = true,
            copado__Main_Branch__c = 'main',
            copado__Platform__c = 'Other',
            copado__Git_Repository__c = repo.Id
        );
        insert pipeline;

        copado__Pipeline_Action__c versionAction = new copado__Pipeline_Action__c(
            copado__Action__c = 'CreatePackageVersion',
            copado__Job_Template__c = jobTemplate.Id,
            copado__Pipeline__c = pipeline.Id
        );
        insert versionAction;

        List<copado__Deployment_Flow_Step__c> pipelineConnections = new List<copado__Deployment_Flow_Step__c>();
        copado__Deployment_Flow_Step__c pipelineConnectionDev1 = new copado__Deployment_Flow_Step__c(
            copado__Branch__c = 'dev1',
            copado__Destination_Branch__c = 'int',
            copado__Deployment_Flow__c = pipeline.Id,
            copado__Source_Environment__c = dev1Env.Id,
            copado__Destination_Environment__c = intEnv.Id);
        pipelineConnections.add(pipelineConnectionDev1);
        copado__Deployment_Flow_Step__c pipelineConnectionDev2 = new copado__Deployment_Flow_Step__c(
            copado__Branch__c = 'dev2',
            copado__Destination_Branch__c = 'int',
            copado__Deployment_Flow__c = pipeline.Id,
            copado__Source_Environment__c = dev2Env.Id,
            copado__Destination_Environment__c = intEnv.Id);
        pipelineConnections.add(pipelineConnectionDev2);
        copado__Deployment_Flow_Step__c pipelineConnectionInt = new copado__Deployment_Flow_Step__c(
            copado__Branch__c = 'int',
            copado__Destination_Branch__c = 'uat',
            copado__Deployment_Flow__c = pipeline.Id,
            copado__Source_Environment__c = intEnv.Id,
            copado__Destination_Environment__c = uatEnv.Id);
        pipelineConnections.add(pipelineConnectionInt);
        copado__Deployment_Flow_Step__c pipelineConnectionUat = new copado__Deployment_Flow_Step__c(
            copado__Branch__c = 'uat',
            copado__Destination_Branch__c = 'main',
            copado__Deployment_Flow__c = pipeline.Id,
            copado__Source_Environment__c = uatEnv.Id,
            copado__Destination_Environment__c = prodEnv.Id);
        pipelineConnections.add(pipelineConnectionUat);
        insert pipelineConnections;

        copado__Project__c project = new copado__Project__c(
            Name = 'Test Project',
            copado__Deployment_Flow__c = pipeline.Id);
        insert project;
        
        copado__Release__c release = new copado__Release__c();
        release.Name = 'Release 1';
        release.copado__Version__c = '1.1.1';
        release.copado__Project__c = project.Id;
        insert release;

        copado__User_Story__c us = new copado__User_Story__c(
            copado__User_Story_Title__c = 'Us 1',
            copado__Project__c = project.Id,
        	copado__Release__c = release.Id);
        insert us;
        
        copado__Promotion__c firstPromotion = new copado__Promotion__c(
            copado__Project__c = project.Id,
            copado__Source_Environment__c = uatEnv.Id);
        insert firstPromotion;

        copado__Promoted_User_Story__c promotedUs = new copado__Promoted_User_Story__c(
            copado__User_Story__c = us.Id,
            copado__Promotion__c = firstPromotion.Id);
        insert promotedUs;
        
        copado__Artifact__c packageRecord = new copado__Artifact__c(
            copado__Package_Type__c = 'Unlocked',
            copado__Target_Dev_Hub_Org__c = devHubOrg.Id,
            copado__DefaultBranch__c = 'main',
            copado__DefaultPath__c = 'force/default',
            copado__Artifact_Repository__c = repo.Id,
            copado__Pipeline__c = pipeline.Id
        );
        insert packageRecord;
    }

    private static void enableCopadoLicenses(User stdUser) {
        copado.GlobalAPI copadoGlobalAPI = new copado.GlobalAPI();
        copado.GlobalAPI.UserLicense UL = new copado.GlobalAPI.UserLicense();

        UL.isCADEnabled = false;
        UL.isCCHEnabled = false;
        UL.isCCMEnabled = true;
        UL.isCopadoEnabled = true;
        UL.isCSTEnabled = true;
        UL.userId = stdUser.Id;

        copado.GlobalAPI.LicenseOperationResult result = copadoGlobalAPI.upsertCopadoLicense(UL);
    }

    private static User createUserWithPermissionSet() {
        String orgId = UserInfo.getOrganizationId();
        String dateString = String.valueof(Datetime.now()).replace(' ', '').replace(':', '').replace('-', '');
        Integer randomInt = Integer.valueOf(math.rint(math.random() * 1000000));
        String uniqueName = orgId + dateString + randomInt;

        Profile stdProfile = [select id, name from profile where permissionscustomizeapplication = false and PermissionsViewSetup = true and userType='Standard' order by createddate limit 1];
        User stdUser = new User(
            Alias = uniqueName.substring(18, 23), 
            Email = uniqueName + '@test' + orgId + '.org', 
            EmailEncodingKey = 'UTF-8', 
            FirstName = 'John',
            LastName = 'Doe', 
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US', 
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = uniqueName + '@test' + orgId + '.org',
            IsActive = true,
            ProfileId = stdProfile.Id);

        insert stdUser;

        Map<String, Id> permissionsByName = getPermissions();
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        assignments.add( new PermissionSetAssignment(AssigneeId = stdUser.Id, PermissionSetId = permissionsByName.get('Copado_User')) );
        assignments.add( new PermissionSetAssignment(AssigneeId = stdUser.Id, PermissionSetId = permissionsByName.get('Copado_Job_Engine')) );
        assignments.add( new PermissionSetAssignment(AssigneeId = stdUser.Id, PermissionSetId = permissionsByName.get('Copado_Functions')) );
        assignments.add( new PermissionSetAssignment(AssigneeId = stdUser.Id, PermissionSetId = permissionsByName.get('Quality_Gates_Admin')) );
        assignments.add( new PermissionSetAssignment(AssigneeId = stdUser.Id, PermissionSetId = permissionsByName.get('Configure_Automations')) );
        assignments.add( new PermissionSetAssignment(AssigneeId = stdUser.Id, PermissionSetId = permissionsByName.get('CMC_SFDX_Admin')) );
        
        insert assignments;

        return stdUser;
    }

    private static Map<String, Id> getPermissions() {
        Map<String, Id> permissionsByName = new Map<String, Id>();
        for (PermissionSet permission : [
            SELECT Id, Name FROM PermissionSet
            WHERE Name IN ('Copado_User', 'Copado_Job_Engine', 'Copado_Functions', 'Quality_Gates_Admin', 'Configure_Automations', 'CMC_SFDX_Admin')]) {
            permissionsByName.put(permission.Name, permission.Id);
        }

        return permissionsByName;
    }

    private static User getRunAsUser() {
        Profile stdProfile = [select id, name from profile where permissionscustomizeapplication = false and PermissionsViewSetup = true and userType='Standard' order by createddate limit 1];
        return [SELECT Id FROM User WHERE ProfileId = :stdProfile.Id ORDER BY CreatedDate DESC LIMIT 1];
    }

    // INNER
    public class EventPayload {
        public String data;
        public String errorMessage;
        public Boolean isSuccess = false;

        public EventPayload(Boolean isSuccess, String errorMessage, String data) {
            this.data = data;
            this.isSuccess = isSuccess;
            this.errorMessage = errorMessage;
        }
    }
    
    public class Response {
        public copado__JobExecution__c jobExecution;
    }
}