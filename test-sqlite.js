const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(':memory:');
db.exec('CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT)');
console.log('MISSING ROW:', JSON.stringify(db.prepare('SELECT * FROM users WHERE username = ?').get('test')));
