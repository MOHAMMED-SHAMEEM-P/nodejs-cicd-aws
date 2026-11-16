
const express = require('express');

const app = express();

app.get('/', (req, res) => {
    res.send('Welcome to my CI/CD project!');
});

app.get('/health', (req, res) => {
    res.status(200).json({
        status: 'healthy'
    });
});

if (require.main === module) {
    app.listen(3000, () => {
        console.log('Server running on port 3000');
    });
}

module.exports = app;
