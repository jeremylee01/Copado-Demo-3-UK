public with sharing class OpenAiApiService {

    public class OpenAiWrapper {
        @AuraEnabled
        public Boolean isSuccess { get; set; }

        @AuraEnabled
        public Integer statusCode { get; set; }

        @AuraEnabled
        public String status { get; set; }

        @AuraEnabled
        public String message { get; set; }

        @AuraEnabled
        public String response { get; set; }
    }

    @AuraEnabled
    public static OpenAiWrapper sendRequest(String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:.__OpenAI/v1/chat/completions');
        req.setHeader('Content-Type', 'application/json');
        req.setMethod('POST');
        req.setBody(body);
        req.setTimeout(30000);

        Http http = new Http();
        HTTPResponse res = http.send(req);
        OpenAiWrapper lwcResponse = new OpenAiWrapper();
        lwcResponse.statusCode = res.getStatusCode();
        lwcResponse.status = res.getStatus();

        if (res.getStatusCode() == 200) {
            lwcResponse.isSuccess = true;
            lwcResponse.message = '';
            lwcResponse.response = res.getBody();
        } else {
            lwcResponse.isSuccess = false;

            try {
                Map<String, Object> m = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
                Map<String, Object> e = (Map<String, Object>)m.get('error');
                lwcResponse.message = (String)e.get('message');
                lwcResponse.status = (String)e.get('type');
            } catch(Exception e) {
                System.debug(e);
                lwcResponse.message = e.getMessage();
                lwcResponse.status = e.getTypeName();
            }
        }
        return lwcResponse;
    }
}