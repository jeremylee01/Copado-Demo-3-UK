@isTest
public with sharing class OpenAiApiServiceTest {

  private class SingleRequestMock implements HttpCalloutMock {
    protected Integer code;
    protected String status;
    protected String bodyAsString;
    protected Blob bodyAsBlob;
    protected Map<String, String> responseHeaders;

    public SingleRequestMock(Integer code, String status, String body,
        Map<String, String> responseHeaders) {
      this.code = code;
      this.status = status;
      this.bodyAsString = body;
      this.bodyAsBlob = null;
      this.responseHeaders = responseHeaders;
    }
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse resp = new HttpResponse();
      resp.setStatusCode(code);
      resp.setStatus(status);
      if (bodyAsBlob != null) {
        resp.setBodyAsBlob(bodyAsBlob);
      } else {
        resp.setBody(bodyAsString);
      }

      if (responseHeaders != null) {
        for (String key : responseHeaders.keySet()) {
          resp.setHeader(key, responseHeaders.get(key));
        }
      }
      return resp;
    }
  }

  static testMethod void calloutSuccess() {
    SingleRequestMock errResponse = new SingleRequestMock(200, 'Success',
        '{ "object": "chat.completion", "model": "text-davinci-003", '+
        '"choices":[{"text":"Hello World" }]'+
        '}',null);
    Test.setMock(HttpCalloutMock.class, errResponse);
    try {
      OpenAiApiService.OpenAiWrapper result = OpenAiApiService.sendRequest('');
      System.assertEquals(true, result.isSuccess);
      System.assertEquals(200, result.statusCode);
      System.assertEquals('Success', result.status);
      System.assertEquals('', result.message);
      Map<String, Object> m = (Map<String, Object>)JSON.deserializeUntyped(result.response);
      System.assertEquals('chat.completion', m.get('object'));
      System.assertEquals('text-davinci-003', (String)m.get('model'));
      List<Object> choices = (List<Object>)m.get('choices');
      System.assertEquals(1, choices.size());
      Map<String, Object> choice = (Map<String, Object>)choices.get(0);
      String choiceText = (String)choice.get('text');
      System.assertEquals('Hello World', choiceText);
    } catch(Exception e) {
      system.assert(false, 'Expected success but Exception was caught.');
    }
        }

    static testMethod void calloutBadApiKey() {
      SingleRequestMock errResponse = new SingleRequestMock(401, 'Error',
          '{ "error": {'+
          '"message": "You didn\'t provide an API key. You need to provide your API key in an Authorization header using Bearer auth (i.e. Authorization: Bearer YOUR_KEY), or as the password field (with blank username) if you\'re accessing the API from your browser and are prompted for a username and password. You can obtain an API key from https://platform.openai.com/account/api-keys.",'+
          '"type": "invalid_request_error",'+
          '"param": null, '+
          '"code": null }}',null);
      Test.setMock(HttpCalloutMock.class, errResponse);
      try {
        OpenAiApiService.OpenAiWrapper result = OpenAiApiService.sendRequest('');
        System.assertEquals(false, result.isSuccess);
        System.assertEquals(401, result.statusCode);
        System.assertEquals('invalid_request_error', result.status);
        String expected_message = 'You didn\'t provide an API key. You need to provide your API key in an Authorization header using Bearer auth (i.e. Authorization: Bearer YOUR_KEY), or as the password field (with blank username) if you\'re accessing the API from your browser and are prompted for a username and password. You can obtain an API key from https://platform.openai.com/account/api-keys.';
        System.assertEquals(expected_message, result.message);
      } catch(Exception e) {
        System.assert(false);
      }
    }

    static testMethod void triggerCatchException() {
      SingleRequestMock errResponse = new SingleRequestMock(500, 'Error','<html>Some Other Error</html>',null);
      Test.setMock(HttpCalloutMock.class, errResponse);
      try {
        OpenAiApiService.OpenAiWrapper result = OpenAiApiService.sendRequest('');
        System.assertEquals(false, result.isSuccess);
        System.assertEquals(500, result.statusCode);
        System.assert(result.message.contains('Unexpected character'));
        System.assertEquals('System.JSONException', result.status);
      } catch(Exception e) {
        System.assert(false);
      }
    }
  }