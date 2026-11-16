
const request = require('supertest');
const app = require('../src/server');

describe('Application tests', () => {

    test('Home page should return welcome message', async () => {
        const response = await request(app).get('/');

        expect(response.statusCode).toBe(200);
        expect(response.text).toBe('Welcome to my CI/CD project!');
    });

    test('Health endpoint should return healthy status', async () => {
        const response = await request(app).get('/health');

        expect(response.statusCode).toBe(200);
        expect(response.body.status).toBe('healthy');
    });

});

