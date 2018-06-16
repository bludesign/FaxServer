![Fax Server](https://media.bludesign.biz/fax_server_logo.png)

<p align="center">
	<a href="http://docs.faxserver.apiary.io/">
        <img src="http://img.shields.io/badge/api-documentation-92A8D1.svg" alt="API Documentation">
    </a>
    <a href="https://vapor.codes/">
        <img src="https://img.shields.io/badge/vapor-3.0-blue.svg" alt="Vapor">
    </a>
    <a href="LICENSE">
        <img src="http://img.shields.io/badge/license-MIT-brightgreen.svg" alt="MIT License">
    </a>
    <a href="https://swift.org">
        <img src="http://img.shields.io/badge/swift-4.0-brightgreen.svg" alt="Swift 4.0">
    </a>
</p>
<br>

<p align="center">
	<img src="https://media.bludesign.biz/fax_screenshot2x.png" width="776">
</p>

Fax Server is a server for sending and receiving faxes with the [Twilio Programmable Fax API](https://www.twilio.com/fax). It can also send and receive SMS/MMS messages with the [Twilio SMS API](https://www.twilio.com/sms/api) as well as receive messages with the [Nexmo SMS API](https://www.nexmo.com/products/sms).

### 🏭 Installing

#### Using Docker

The easiest way to install is with [Docker](https://www.docker.com)

    git clone --depth=1 git@github.com:bludesign/FaxServer.git
    cd FaxServer
    docker-compose up

After starting the server will be running at [http://127.0.0.1:8080](http://127.0.0.1:8080)

To run the server in the background run `docker-compose up -d`

#### Manually

If it is not already installed install [MongoDB](https://docs.mongodb.com/manual/installation/) if you are using authentication or a non-standard port set it with the `MONGO_HOST`, `MONGO_PORT`, `MONGO_USERNAME`, `MONGO_PASSWORD` environment variables.

Next install Vapor and Swift here for [macOS](https://docs.vapor.codes/2.0/getting-started/install-on-macos/) or  [Ubuntu](https://docs.vapor.codes/2.0/getting-started/install-on-ubuntu/).

Then build and run the project:

    git clone --depth=1 git@github.com:bludesign/FaxServer.git
    cd FaxServer
    vapor build --release
    .build/release/App

The server will now be running at [http://127.0.0.1:8080](http://127.0.0.1:8080). Note running the server with `vapor run serve` will not work it must be run directly with the `App` in `.build/release` directory.

### 🚀 Deploy

The server must be reachable from the internet which can be done using  [Nginx](https://docs.vapor.codes/2.0/deploy/nginx/#configure-proxy) (Recommended) or [Apache2](https://docs.vapor.codes/2.0/deploy/apache2/).

If using Nginx the `client_max_body_size` must be increased to allow for larger PDF file uploads.

Example Nginx Config:

    server {
        listen 80;
    	client_max_body_size 20M;

        location / {
            proxy_set_header   Host $http_host;
            proxy_pass         http://127.0.0.1:8080;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_pass_header Server;
            proxy_connect_timeout 3s;
            proxy_read_timeout 10s;
        }
    }

### 🔧 Configuration

First visit the Fax Server's address and register a new user account after you create your account you should disable user registration in settings.

#### Twilio Configuration

![Fax Server](https://media.bludesign.biz/fax_twilio.png)

- Open the [Manage Active Numbers](https://www.twilio.com/console/phone-numbers/incoming) page on Twilio.
- For each number you will be using configure Twilio to forward faxes and if you want SMS then messages to your server.
- Use `https://(Server Address Here)/fax/twiml` and `https://(Server Address Here)/message/twiml` for the webhooks.
- Visit the [Twilio Account](https://www.twilio.com/console/account/settings) page to get your Account SID and Auth Token.

#### Nexmo Configuration (Optional)

> SMS messages can only be received from Nexmo so no accounts need to be added in Fax Server to receive messages.

- In your Nexmo account settings under API settings make sure the HTTP method is set to POST.
- Under Numbers in Nexmo set the SMS webhook URL to `https://(Server Address Here)/message/nexmo`
- Nexmo must be enabled in Fax Server settings if it has been disabled.

#### Fax Server Configuration

- Login to Fax Server and click on Accounts.
- Create an account for each phone number you will be using for faxing or SMS messaging using the Twilio phone number, account SID and Auth Token from above.
- If you have multiple phone numbers for the same Twilio account create separate accounts in Fax Server for each phone number using the same Account SID and Auth Token for each.
- For email notifications setup an account with [Mailgun](https://signup.mailgun.com/new/signup) and set the email addresses, Mailgun API Key and Mailgun API URL in Fax Server Settings.

> It is possible to add phone numbers to Fax Server that are not in your Twilio account but have been [verified](https://support.twilio.com/hc/en-us/articles/223180048-Adding-a-verified-outbound-caller-ID-with-Twilio) this can be used to add a number such as a regular fax machine allowing you to send faxes from Fax Server and still receive them on a regular fax machine. Note this does not apply to SMS messages, SMS messages can only be sent from Twilio numbers they can not be sent from Twilio verified numbers.

### 🔒 **Important** - Securing Fax Server

- **[Must Be Done]** Disable user registration in Fax Server settings after setting up your user account so that new users can not be created. Note you can always create new users in the Users section this only disables anonymous user creation.
- **[Strongly Recommended]** Setup HTTPS on the proxy server (Nginx or Apache2) see tutorial [here](https://www.digitalocean.com/community/tutorials/how-to-secure-nginx-with-let-s-encrypt-on-ubuntu-16-04).
- [Advanced Users] Enabled secure (HTTPS Only) cookies in settings. This should only be done if you only access your server over a HTTPS connection and will restrict logins to HTTPS only. Note if you enable this you will not be able to sign in over an insecure (HTTP) connection to turn if off.
- [Advanced Users] Enable 2 factor authentication (TOTP) login, under Users select your user account and activate 2 factor authentication. Note there is no way to reset this if you loose your TOTP secret key.
- [Advanced Users] If you will not be receiving Nexmo SMS messages the webhook can be disabled in Fax Server settings.

### 📱 iOS App Setup

![Fax Server](https://media.bludesign.biz/fax_client.png)

- Open Clients in Fax Server and create a client with the above values.
- After creating the client copy the Client ID and Client Secret and fill them into the iOS app along with your servers URL.

<p align="center">
	<a href="https://itunes.apple.com/us/app/fax-server/id1331048085?ls=1&mt=8">
		<img src="https://media.bludesign.biz/appstore.svg" alt="App Store">
	</a>
</p>
