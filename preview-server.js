const http = require('http');
const fs = require('fs');
const path = require('path');

http.createServer((request, response) => {
  fs.readFile(path.join(__dirname, 'index.html'), (error, html) => {
    response.writeHead(error ? 500 : 200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    response.end(error ? 'Unable to load index.html' : html);
  });
}).listen(8000, '127.0.0.1');
