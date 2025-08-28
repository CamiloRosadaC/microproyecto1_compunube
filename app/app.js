const http = require('http');
const os = require('os');
const name = process.env.APP_NAME || os.hostname();
const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type':'text/plain'});
  res.end(`Hello from ${name}\n`);
});
server.listen(3000, () => console.log(`Listening on 3000 - ${name}`));
