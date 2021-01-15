import { default as express } from 'express';

/*  if using mongodb, uncomment this block:

import { default }
*/

if (process.env.PORT === undefined)
    throw new Error(`Please specify a port and try again.`)
else {
    const port = process.env.PORT;
    const app = express();
    app.use(express.json())

    app.get(`/`, (req, res) => {
        res.send('Hello world!');
    });

    console.log(`Listening on port ${port}.`);
    app.listen(port);
}

process.on('SIGINT', function () {
    console.log("\nGracefully shutting down from SIGINT (Ctrl-C)");
    process.exit(1);
});