public with sharing class OpenAIQuestionProcessor {

    @AuraEnabled
    public static String processQuestion(Id contextId, String question) {
        String sobjectName = contextId.getSobjectType().getDescribe().getName();
        switch on sobjectName {
            when 'copado__Promotion__c' {
                return getPromotionDataForQuestion(contextId, question);
            }
            when 'copado__Deployment__c' {
                return getDeploymentForQuestion(contextId, question);
            }
            when 'copado__User_Story__c' {
                return getUserStoryForQuestion(contextId, question);
            }
            when else {
                return 'Sorry, I cannot understand the details of the object: '+sobjectName;
            }
        }
    }

    @AuraEnabled
    public static String[] getAvailableQuestionsFor(Id contextId) {
        String sobjectName = contextId.getSobjectType().getDescribe().getName();
        switch on sobjectName {
            when 'copado__Promotion__c' {
                return new String[]{
                    'Can you explain me the following salesforce deployment errors and what can I do to correct them?\n{deploymenterrors}', 
                    'Based on the following log lines, can you show the total time it took, identify the 3 slowest tasks and show how long each took? do note there is a timestamp on each line:\n{logs}', 
                    'Can you create the release notes of the following list of user stories:\n{userstorylist}', 
                    'These are the salesforce deployment errors:\n{deploymenterrors}\n...', 
                    'These are the promotion logs:\n{logs}\n\n...', 
                    'These are the user stories:\n{userstorylist}\n...'
                };
            }
            when 'copado__Deployment__c' {
                return new String[]{
                    'Can you explain me the following salesforce deployment errors and what can I do to correct them?\n{deploymenterrors}', 
                    'Based on the following log lines, can you show the total time it took, identify the 3 slowest tasks and show how long each took? do note there is a timestamp on each line:\n{logs}', 
                    'Can you create the release notes of the following list of user stories:\n\n{userstorylist}', 
                    'These are the salesforce deployment errors:\n{deploymenterrors}\n...', 
                    'These are the deployment logs:\n{logs}\n\n...', 
                    'These are the user stories:\n{userstorylist}\n...'
                };
            }
            when 'copado__User_Story__c' {
                return new String[]{
                    'Help me improve and fill out missing fields on this User Story that currently has the following information, and preserve the numbered list format with the field names\n\n1) Title: {title}\n\n2) Functional specifications: {functional specifications}\n\n3) Technical specifications: {technical specifications}\n\n4) As a...: {as a}\n\n5) Want to...: {want to}\n\n6) So that...: {so that}\n\n7) Acceptance Criteria: {acceptance criteria}\n\n8) Associated Feature: {feature}\n\n9) Associated Epic: {epic}\n\n10) Feature description: {feature description}\n\n11) Feature technical assumptions: {feature technical assumptions}\n\n12) Epic description: {epic description}\n\n13) Epic details: {epic details}\n\n14) Epic technical assumptions: {epic technical assumptions}\n\n15) Project: {project}\n\n16) Project Description: {project description}\n',
                    'This is the numbered list of fields and their values in the User Story...\n\n1) Title: {title}\n\n2) Functional specifications: {functional specifications}\n\n3) Technical specifications: {technical specifications}\n\n4) As a...: {as a}\n\n5) Want to...: {want to}\n\n6) So that...: {so that}\n\n7) Acceptance Criteria: {acceptance criteria}\n\n8) Associated Feature: {feature}\n\n9) Associated Epic: {epic}\n\n10) Feature description: {feature description}\n\n11) Feature technical assumptions: {feature technical assumptions}\n\n12) Epic description: {epic description}\n\n13) Epic details: {epic details}\n\n14) Epic technical assumptions: {epic technical assumptions}\n\n15) Project: {project}\n\n16) Project Description: {project description}\n\n...'
                };
            }
            when else {
                return new String[]{
                    '(there are no predefined questions for '+sobjectName+')'
                };
            }
        }
    }

    /**
     * Based on a promotion Id and the template of a question, return the text to be sent to OpenAI
     */
    private static String getPromotionDataForQuestion(Id promotionId, String question) {
        String logs = '';
        String deploymentErrors = '';
        String userStoryList = '';
        String lastDeploymentId;
        Boolean isClassic;

        copado__Promotion__c promotion = [SELECT copado__Status__c, copado__Platform__c,
            (SELECT Title, Body FROM Notes ORDER By CreatedDate DESC LIMIT 1), 
            (SELECT Id FROM copado__Deployments__r ORDER BY CreatedDate DESC LIMIT 1),
            (SELECT copado__User_Story__r.Name, copado__User_Story__r.copado__User_Story_Title__c 
                FROM copado__Promoted_User_Stories__r ORDER BY Name DESC LIMIT 200)
            FROM copado__Promotion__c WHERE Id = :promotionId WITH SECURITY_ENFORCED LIMIT 1];

        // the user story list is the same for 1st and 2nd gen
        for(copado__Promoted_User_Story__c pus : promotion.copado__Promoted_User_Stories__r) {
            userStoryList += pus.copado__User_Story__r.Name+' '+pus.copado__User_Story__r.copado__User_Story_Title__c+'\n';
        }

        isClassic = String.isEmpty(promotion.copado__Platform__c) || promotion.copado__Platform__c=='Salesforce';
        lastDeploymentId = promotion.copado__Deployments__r.size() >0 ? promotion.copado__Deployments__r[0].Id : null;

        // check if the US is 1stgen or 2ndgen based on copado__Platform__c
        if(isClassic) {
            logs = promotion.Notes.size()>0 ? promotion.Notes[0].Body : null;
            // TODO: check the SIZE of the file, to avoid memory errors, and also chatgpt limits (?)
            deploymentErrors = [SELECT Body FROM Attachment WHERE ParentId = :lastDeploymentId AND Name LIKE 'ERRORs%.txt' ORDER BY CreatedDate DESC LIMIT 1]?.Body?.toString();
        }

        Map<String, String> params = new Map<String, String>{
            'logs' => logs,
            'deploymenterrors' => deploymenterrors,
            'userstorylist' => userstorylist,
            '' => ''
        };
        question = processQuestionParams(question, params);

        return question;
    }

    private static String getDeploymentForQuestion(Id deploymentId, String question) {
        String logs = '';
        String deploymentErrors = '';
        String userStoryList = '';
        Boolean isClassic;

        copado__Deployment__c deployment = [SELECT copado__Promotion__c FROM copado__Deployment__c WHERE Id = :deploymentId WITH SECURITY_ENFORCED LIMIT 1];
        String promotionId = deployment.copado__Promotion__c;

        copado__Promotion__c promotion = [SELECT copado__Status__c, copado__Platform__c,
            (SELECT Id FROM copado__Deployments__r ORDER BY CreatedDate DESC LIMIT 1),
            (SELECT copado__User_Story__r.Name, copado__User_Story__r.copado__User_Story_Title__c 
                FROM copado__Promoted_User_Stories__r  ORDER BY Name DESC LIMIT 200)
            FROM copado__Promotion__c WHERE Id = :promotionId WITH SECURITY_ENFORCED LIMIT 1];

        isClassic = String.isEmpty(promotion.copado__Platform__c) || promotion.copado__Platform__c=='Salesforce';

        // the user story list is the same for 1st and 2nd gen
        for(copado__Promoted_User_Story__c pus : promotion.copado__Promoted_User_Stories__r) {
            userStoryList += pus.copado__User_Story__r.Name+' '+pus.copado__User_Story__r.copado__User_Story_Title__c+'\n';
        }

        // check if the US is 1stgen or 2ndgen based on copado__Platform__c
        if(isClassic) {
            copado__Step__c[] steps = [SELECT Id, 
                (SELECT Id FROM copado__Deployment_Jobs__r ORDER BY CreatedDate DESC LIMIT 1) 
                    FROM copado__Step__c WHERE copado__Deployment__c = :deploymentId 
                    AND copado__Type__c = 'Git Promotion' WITH SECURITY_ENFORCED LIMIT 1];
            Id lastJobId = (!steps.isEmpty() && !steps[0].copado__Deployment_Jobs__r.isEmpty())
                ? steps[0].copado__Deployment_Jobs__r[0].Id
                :null;
            Note[] notes = [SELECT Title, Body FROM Note WHERE ParentId = :lastJobId WITH SECURITY_ENFORCED ORDER By CreatedDate DESC LIMIT 1];
            logs = notes.isEmpty() ? '' : notes[0].Body;

            // TODO: check the SIZE of the file, to avoid memory errors, and also chatgpt limits (?)
            deploymentErrors = [SELECT Body FROM Attachment WHERE ParentId = :deploymentId AND Name LIKE 'ERRORs%.txt' ORDER BY CreatedDate DESC LIMIT 1]?.Body?.toString();
        }

        Map<String, String> params = new Map<String, String>{
            'logs' => logs,
            'deploymenterrors' => deploymenterrors,
            'userstorylist' => userstorylist,
            '' => ''
        };
        question = processQuestionParams(question, params);

        return question;
    }

    private static String getUserStoryForQuestion(Id userStoryId, String question) {
        String userStoryDetails = '';
        // We MOCK the promotion object, because setting up unit-tests for copado objects requires permissions, licenses, and hundreds of lines of very complex code
        copado__User_Story__c userStory = [SELECT 
            copado__User_Story_Title__c, 
            copado__Acceptance_Criteria__c,
            copado__userStory_Role__c, 
            copado__userStory_need__c, 
            copado__userStory_reason__c,
            copado__Functional_Specifications__c, 
            copado__Technical_Specifications__c,
            copado__Project__r.Name,
            copado__Project__r.copado__Description__c,
            copado__Epic__r.copado__Epic_Title__c,
            copado__Epic__r.copado__Description__c,
            copado__Epic__r.copado__Epic_Details__c,
            copado__Epic__r.copado__Technical_Assumptions__c,
            copado__US_Feature__r.Name,
            copado__US_Feature__r.copado__Description__c,
            copado__US_Feature__r.copado__Technical_Assumptions__c
            FROM copado__User_Story__c WHERE Id = :userStoryId WITH SECURITY_ENFORCED LIMIT 1];

        Map<String, String> params = new Map<String, String>{
            'title' => userStory.copado__User_Story_Title__c,
            'project' => userStory.copado__Project__r.Name,
            'project description' => userStory.copado__Project__r.copado__Description__c,
            'epic' => userStory.copado__Epic__r.copado__Epic_Title__c,
            'epic description' => userStory.copado__Epic__r.copado__Description__c,
            'epic details' => userStory.copado__Epic__r.copado__Epic_Details__c,
            'epic technical assumptions' => userStory.copado__Epic__r.copado__Technical_Assumptions__c,
            'feature' => userStory.copado__US_Feature__r.Name,
            'feature description' => userStory.copado__US_Feature__r.copado__Description__c,
            'feature technical assumptions' => userStory.copado__US_Feature__r.copado__Technical_Assumptions__c,
            'acceptance criteria' => userStory.copado__Acceptance_Criteria__c,
            'functional specifications' => userStory.copado__Functional_Specifications__c,
            'technical specifications' => userStory.copado__Technical_Specifications__c,
            'as a' => userStory.copado__userStory_Role__c,
            'want to' => userStory.copado__userStory_need__c,
            'so that' => userStory.copado__userStory_reason__c,
            '' => ''
        };
        question = processQuestionParams(question, params);

        return question;
    }

    private static String processQuestionParams(String question, Map<String, String> params) {
        for(String key : params.keySet()) {
            String value = textWithName(key, params.get(key));
            question = question.replace('{'+key+'}', ''+value);
        }
        return question;
    }

    private static String textWithName(String name, String value) {
        value = String.isBlank(value) ?'' :value; // null check first
        if(value.startsWith('<')) {
            // consider this rich text... converting it is REALLY annoying due to stripHtmlTags() removing whitespaces
            value = value
                .replaceAll('<\\s*li\\s*>', '~á~')
                .replaceAll('<\\s*/?\\s*(?:p|br|li|div|h\\d|tr|dt|blockquote)\\s*/?\\s*>', '~ñ~')
                .stripHtmlTags().replaceAll('~ñ~', '\n').replaceAll('~á~', '\n- ')
                .replaceAll('\n\n', '\n').replaceAll('\n\n', '\n').replaceAll('\n\n', '\n');
            System.debug(value);
            value = '\n'+value;
        }else if(value.contains('\n')) {
            value = '\n'+value;
        }
        value = String.isBlank(value) ?'(empty)' :value; // add an empty text marker
        return value;
    }
}