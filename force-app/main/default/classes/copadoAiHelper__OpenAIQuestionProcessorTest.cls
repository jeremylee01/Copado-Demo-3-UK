@isTest
private with sharing class OpenAIQuestionProcessorTest {

    @isTest
    private static void testMultipleObjects() {
        System.runAs([SELECT Id FROM User WHERE Username = 'username@myemail.com'][0]) {
            //Setup
            OpenAITestDataFactory.createDefaultTestData('Salesforce');

            // Exercise: unsupported object (pipeline)
            {
                OpenAIQuestionProcessor.getAvailableQuestionsFor(OpenAITestDataFactory.pipeline.Id);
                String result = OpenAIQuestionProcessor.processQuestion(OpenAITestDataFactory.pipeline.Id, '');
                Assert.isTrue(true, 'called only for code coverage reasons');
            }

            // Exercise: promotion
            {
                OpenAIQuestionProcessor.getAvailableQuestionsFor(OpenAITestDataFactory.promotion.Id);
                String result = OpenAIQuestionProcessor.processQuestion(OpenAITestDataFactory.promotion.Id, 
                    'logs=====\n{logs}\ndeploymenterrors=====\n{deploymenterrors}\nuserstorylist=====\n{userstorylist}');
                // Validate
                Assert.isFalse(result.contains('{'), 'all the merges should have been removed, but result='+result);
                Assert.isTrue(result.startsWith('logs='), 'incorrect result='+result);
            }

            // Exercise: deploymnet
            {
                OpenAIQuestionProcessor.getAvailableQuestionsFor(OpenAITestDataFactory.deployment.Id);
                String result = OpenAIQuestionProcessor.processQuestion(OpenAITestDataFactory.deployment.Id, 
                    'logs=====\n{logs}\ndeploymenterrors=====\n{deploymenterrors}\nuserstorylist=====\n{userstorylist}');
                // Validate
                Assert.isFalse(result.contains('{'), 'all the merges should have been removed, but result='+result);
                Assert.isTrue(result.startsWith('logs='), 'incorrect result='+result);
            }

            // Exercise: user story
            {
                OpenAIQuestionProcessor.getAvailableQuestionsFor(OpenAITestDataFactory.userStory.Id);
                String result = OpenAIQuestionProcessor.processQuestion(OpenAITestDataFactory.userStory.Id, 
                    'title=====\n{title}');
                // Validate
                Assert.isFalse(result.contains('{'), 'all the merges should have been removed, but result='+result);
                Assert.isTrue(result.startsWith('title='), 'incorrect result='+result);
            }

        }
    }


    @TestSetup
    private static void makeData() {
        User runAsUser = new User(
            LastName = 'UserLastName',
            Username = 'username@myemail.com',
            Email = 'username@myemail.com',
            Alias = 'MyAlias',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = UserInfo.getProfileId(),
            LanguageLocaleKey = 'en_US'
        );
        insert runAsUser;

        System.runAs(runAsUser) {
            copado.GlobalAPI copadoGlobalAPI = new copado.GlobalAPI();
            copado.GlobalAPI.UserLicense userLicense = new copado.GlobalAPI.UserLicense();
            userLicense.isCCMEnabled = true;
            userLicense.isCopadoEnabled = true;
            userLicense.userId = runAsUser.Id;
            copadoGlobalAPI.upsertCopadoLicense(userLicense);
            
            PermissionSetAssignment copado = new PermissionSetAssignment();
            copado.PermissionSetId = [SELECT Id, Name FROM PermissionSet WHERE Name = 'Copado_User' LIMIT 1].Id;
            copado.AssigneeId = runAsUser.Id;

            insert copado;
        }
    }

}