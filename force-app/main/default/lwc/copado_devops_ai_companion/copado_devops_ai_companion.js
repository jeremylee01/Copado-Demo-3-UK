import { api, track, wire } from 'lwc';
import Id from '@salesforce/user/Id';
import Name from '@salesforce/schema/User.Name';
import { LightningElement } from 'lwc';
import callOpenAiApi from '@salesforce/apex/OpenAiApiService.sendRequest';
import processQuestion from '@salesforce/apex/OpenAIQuestionProcessor.processQuestion';
import getAvailableQuestionsFor from '@salesforce/apex/OpenAIQuestionProcessor.getAvailableQuestionsFor';
import { getRecord } from 'lightning/uiRecordApi';

const CONTINUE = 'Please continue';

export default class Copado_devops_ai_companion extends LightningElement {
    @api contextId;
    @api max_tokens;
    @api temperature;
    @api engine;
    @track username;

    userMessage;
    selectedQuestion;
    isLoading = false;
    more = false;
    availableQuestions = [];

    @track messages = [];

    @wire(getRecord, { recordId: Id, fields: [Name] })
    currentUserInfo({ error, data }) {
        if (data) {
            this.username = data.fields.Name.value;
        } else if (error) {
            this.error = error ;
        }
    }

    connectedCallback() {
        this.template.addEventListener('openaicontinue', this.handleSubmit.bind(this));

        getAvailableQuestionsFor({ contextId: this.contextId })
            .then((result) => {
                this.availableQuestions = result.map(x => ({label: x, value: x}));
            })
            .catch((err) => {
                console.error(err);
                let userError = err.body
                    ? (err.body.message ? `${err?.body?.message}\n${err.body.exceptionType}\n${err.body.stackTrace}` : err.body)
                    : err;
                this.addMessage('* There was an error: '+userError, false);
            });
    }

    renderedCallback() {
        this.scrollToBottom();
    }

    scrollToBottom() {
        const scrollArea = this.template.querySelector('lightning-textarea');
        scrollArea.scrollTop = scrollArea.scrollHeight;
        scrollArea.scrollIntoView();
    }

    get hasMessages() {
        return this.messages.length > 0;
    }

    handleUserMesssage(event){
        this.userMessage = event.target.value;
    }

    handleClear() {
        this.selectedQuestion = undefined;
        this.userMessage = '';
        this.messages = [];
        const textArea = this.template.querySelector("lightning-textarea");
        textArea.value = "";
        textArea.placeholder = 'review/edit the information to be sent...';
    }

    async handleSelectQuestion(event) {
        this.selectedQuestion = event.detail.value;

        processQuestion({
            contextId: this.contextId,
            question: this.selectedQuestion
        }).then((result) => {
            this.userMessage = result;
            const textArea = this.template.querySelector('lightning-textarea');
            textArea.value = this.userMessage;
            textArea.selectionEnd = textArea.value.toString().length;
            textArea.focus();
        }).catch((err) => {
            console.error(err);
            let userError = err.body
                ? (err.body.message ? `${err?.body?.message}\n${err.body.exceptionType}\n${err.body.stackTrace}` : err.body)
                : err;
            this.addMessage('* There was an error: '+userError, false);
        });
    }

    async handleSubmit(event) {
        if (event.type === 'openaicontinue') {
            event.stopPropagation();
        }

        try {
            if(!this.userMessage && event.type !== 'openaicontinue') {
                return
            }

            this.isLoading = true;

            // add the last user message to the queue, and clear the input
            if (event.type !== 'openaicontinue') {
                this.addMessage(this.userMessage, true);
                this.userMessage = '';
            }
            this.scrollToBottom();

            let chatGPTmessages = [{
                "role": "system",
                "content": "You need to assist the person asking you questions and tasks about Copado. Copado is a Salesforce Devops and Deployment tool, and most of changes in User Stories, Promotions and Deployments are related to Salesforce features and Salesforce metadata"
            }];

            chatGPTmessages = chatGPTmessages.concat(this.messages.map((m) => ({
                content: m.content,
                role: m.role,
            })));

            if (event.type === 'openaicontinue') {
                chatGPTmessages.push({
                    content: CONTINUE,
                    role: 'user',
                });
            }

            const body = JSON.stringify({
                'model': this.engine || 'gpt-3.5-turbo',
                'messages': chatGPTmessages,
                'max_tokens': Number(this.max_tokens || 200),
                'temperature': Number(this.temperature || 1),
                'top_p': 1,
                'stream': false
            });

            const data = await callOpenAiApi({ body });

            if (!data.isSuccess) {
                throw new Error(data.message || data);
            }

            let response = JSON.parse(data.response);
            const more = response.choices[0].finish_reason !== 'stop';
            if(event.type === 'openaicontinue') {
                // append to that message.
                this.messages[this.messages.length - 1].content += ' ' + response.choices[0].message.content.trim();
                this.messages[this.messages.length - 1].more = more;
            } else {
                this.addMessage(response.choices[0].message.content.trim(), false, more);
            }

            const textArea = this.template.querySelector('lightning-textarea');

            textArea.placeholder = 'ask follow-up questions or additional instructions...';

        } catch(err) {
            console.error(err);
            let userError = err.body
                ? (err.body.message ? `${err?.body?.message}\n${err.body.exceptionType}\n${err.body.stackTrace}` : err.body)
                : err;
            this.addMessage('* There was an error: '+userError, false);
        } finally {
            this.isLoading = false;
            this.scrollToBottom();
        }
    }

    addMessage(content, fromUser, more) {
        this.messages.push({
            timestamp: this.messages.length,
            content: '' + content,
            role: fromUser ? 'user' : 'system',
            more,
        });
    }
}