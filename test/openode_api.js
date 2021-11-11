
const http = require("http");

const port = 3000
console.log(`Port is ${port}`)

const server = http.createServer(function (req, res) {
    console.log(`Request on ${req.url}`)
    
    if (req.url === '/super_admin/website_locations/load_balancer_requiring_sync') {
        res.end(
            `[{"hosts": ["mytest.openode.io"], "id": 10, "website_id": 999, "backend_url": "https://www.openode.io/"}]`
        );
    }
    else if (req.url === '/super_admin/website_locations/online/gcloud_run') {
        res.end(
            `[{"hosts": ["myboottest.openode.io"], "id": 11, "website_id": 1000, "backend_url": "https://raw.githubusercontent.com/openode-io/openode-rproxy/master/server.rb"}]`
        );
    }
    else if (req.url === '/super_admin/website_locations/10') {
        res.end(`{}`);   
    }
    else {
        res.end(`!!Hello opeNode World`);
    }
}).listen(port, (err) => {
    if ( ! err) {
        console.log(`node server listening on port ${port}...`, new Date())
    }
})
