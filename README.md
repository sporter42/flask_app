# Deploying a Flask App to AWS EC2
#### Using GitHub, AWS CodeDeploy, AWS CodePipeline, and Amazon EC2 (Apache on Ubuntu)

Sections of this walk-through:

1. [Create a Basic Flask App](#create-a-basic-flask-app)
2. [AppSpec YAML and Deployment Scripting](#appspec-yaml-and-deployment-scripting)
3. [Apache Configuration](#apache-configuration)
4. [EC2 Instance Setup](#ec2-instance-setup)
5. [AWS CodeDeploy and CodePipeline Setup](#aws-codedeploy-and-codepipeline-setup)

(This walk-through assumes you're working on a macOS or Linux computer with Python 3 installed and that you know how to use git. If you're using Windows, some of the commands may be somewhat different.)

## Create a Basic Flask App

Before you create a basic Flask app, [create your repo](https://docs.github.com/en/get-started/quickstart/create-a-repo) on GitHub and [clone it](https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository) onto your computer. I recommend using the .gitignore template for Python, so venv and pycache will be excluded from your repo.

Then, create a basic Flask app with a virtual environment within that repo.

Run the following commands to initialize your Flask virtual environment.
```bash
$ cd {where your repo lives}
$ mkdir source
$ cd source
$ python3 -m venv venv
$ source venv/bin/activate
(venv) $ pip3 install Flask
(venv) $ pip3 freeze > requirements.txt
(venv) $ touch run.py
(venv) $ touch production.wsgi
(venv) $ mkdir templates
(venv) $ touch templates/index.html
```

Then edit the following files, which constitute a very basic Flask app.

#### source/run.py:
```python
from flask import Flask, render_template

app = Flask(__name__)

@app.route('/')
def home():
    return render_template('index.html', title='Flasky', content='Hello, world')

if __name__ == "__main__":
   app.run(host='0.0.0.0', port=5080, debug=True)
```

#### source/templates/index.html:
```html
<html>
<head>
    <title>{{ title }}</title>
</head>
<body>
<h1>{{ title }}</h1>
<div>{{ content }}</div>
</body>
```

At this point you should be able to run your app locally...

```bash
(venv) $ python3 run.py
```

...and access it in your browser at [http://127.0.0.1:5080](http://127.0.0.1:5080)

Next, add the following files.

#### source/requirements.txt:
```
Flask
```

This file is used by pip to install any needed Python modules. For this simple app, we only need Flask.


#### source/production.wsgi:
```python
import sys
 
sys.path.insert(0, '/var/www/html/flask_app/')
 
from run import app as application
```

(The `/var/www/html/flask_app/` path means nothing for you but will be used when you deploy to an EC2 instance.)

## AppSpec YAML and Deployment Scripting

To deploy an app using AWSCodeDeploy, you'll need an [AppSpec File](https://docs.aws.amazon.com/codedeploy/latest/userguide/reference-appspec-file-example.html#appspec-file-example-server) and accompanying shell scripts. The AppSpec File tells CodeDeploy where to place files and what commands to run at different steps of a deployment. Create the folowing AppSpec File and accompanying shell scripts:

#### appspec.yml:
```yaml
version: 0.0
os: linux

files:
  - source: source
    destination: /home/ubuntu/flask_app
  - source: flask_app.conf
    destination: /etc/apache2/sites-available
file_exists_behavior: OVERWRITE

hooks:
  ApplicationStop:
    - location: aws-scripts/app-stop.sh
      timeout: 300

  AfterInstall:
    - location: aws-scripts/after-install.sh
      timeout: 300

  ApplicationStart:
    - location: aws-scripts/app-start.sh
      timeout: 300
```

This AppSpec File tells CodeDeploy:

- copy source/* from your repo to /home/ubuntu/flask_app/
- copy flask_app.conf from your repo to /etc/apache2/sites-available/flask_app.conf
- the shell scripts to run:
    - to stop your application
    - after the install
    - to start your application

#### aws-scripts/app-stop.sh:
```bash
sudo systemctl stop apache2
```

#### aws-scripts/after-install.sh:
```bash
# create venv and install required packages
cd /home/ubuntu/flask_app
python3 -m venv venv
venv/bin/pip3 install -r requirements.txt
# add soft link
if [ ! -h /var/www/html/flask_app ]; then
	sudo ln -sT /home/ubuntu/flask_app /var/www/html/flask_app
fi
# enable site
sudo a2ensite flask_app
sudo systemctl reload apache
```

#### aws-scripts/app-start.sh:
```bash
sudo systemctl start apache2
```

## Apache Configuration

Apache configuration is split into two parts. One part is the conf file for your site. That's right here. This file is put in place by CodeDeploy, as configured in the AppSpec File. 

The other part, installing Apache and mod_wsgi on your EC2 instance, is part of [EC2 Instance Setup](#ec2-instance-setup), below.

#### flask_app.conf:
```Apache
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/flask_app
    WSGIDaemonProcess flask_app python-home=/var/www/html/flask_app/venv
    WSGIScriptAlias / /var/www/html/flask_app/production.wsgi

    <Directory /var/www/html/flask_app>
         Options FollowSymLinks
         AllowOverride All
         Require all granted

         WSGIProcessGroup flask_app
         WSGIApplicationGroup %{GLOBAL}
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
```

## Files in Your Repo
After completing the first three parts of this walk-through, organize the files in your repo as shown below. 

- .gitignore
- appspec.yml
- flask_app.conf
- aws-scripts/
    - after-install.sh
    - app-start.sh
    - app-stop.sh
- source/
    - run.py
    - production.wsgi
    - requirements.txt
    - templates/
        - index.html

(Your local filesystem will also contain source/venv, which you don't want to commit to your repo.)

If you haven't already, commit these changes and push them to GitHub.

## EC2 Instance Setup

In *AWS Console > EC2*, select *Launch Instances* and configure your instance as follows:

- Name and tags (you'll have to *Add tag* to add the second tag)
	1. Key=Name; Value=flask-server (or whatever you wish)
	2. Key=flask_app_deploy_target; Value=true
- OS: Ubuntu Server 20.04 LTS (HVM), SSD Volume Type
- Architecture: 64-bit (x86) 
- Instance type: t2.micro (Free Tier Eligible; or whatever you wish)
- Key pair: Existing (if you have one and know how to use it) or no key pair (not recommended) set one up now (outside the scope of this walk-through)
- Firewall (security groups): Existing (if you have one for web servers) or Allow SSH traffic from My IP & Allow HTTP/HTTPS traffic from the internet
- User Data: Paste in the server setup script, below. See the inline comments for what the different blocks of commands are for. (Alternatively: ssh into the server after it boots and run these commands interactively.) Replace "us-east-1" (twice) with the AWS region identifier your instance is in.

(Regarding the *key pair*: You might be able to get by without ever having to ssh into this server, but I'd still set up a key pair. See [this documenation from AWS](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html) for more information about EC2 instances and key pairs.)

#### Server setup script (aka *User data*):
``` {.bash}
#!/bin/bash
sudo apt-get update
# install awscli
sudo apt install -y awscli
# install python3, apache2, mod_wsgi
sudo apt install -y python3-pip
sudo apt install -y python3-venv
sudo apt install -y apache2
sudo apt install -y libapache2-mod-wsgi-py3
# install certbot
sudo apt remove certbot
sudo snap install core
sudo snap refresh core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
# apache: disable default site
sudo a2dissite 000-default.conf
# install codedeploy agent
sudo apt install -y ruby-full
sudo apt install -y wget
cd ~
wget https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto
```

Click "Launch Instance" to create the instance. 

After a minute or so, you should be able to access the instance via ssh or https. The default site has been disabled but Apache wasn't restarted for that change to take effect, so you should be able to access it via your browser -- http://{public IPv4 address}

(It might take a few minutes for the instance to boot and for the server setup script to complete. The next steps should take long enough that it won't be an issue. But if you're doing things out-of-order, this is something to keep in mind.)

## AWS CodeDeploy and CodePipeline

Before you can configure CodeDeploy, you need to create an IAM Service Role for CodeDeploy and an IAM Instance Profile for your EC2 Instance. AWS provides excellent instructions for completing these steps:

- [Create a service role for CodeDeploy](https://docs.aws.amazon.com/codedeploy/latest/userguide/getting-started-create-service-role.html)
- [Create an IAM instance profile for your Amazon EC2 instances](https://docs.aws.amazon.com/codedeploy/latest/userguide/getting-started-create-iam-instance-profile.html)

You'll need to associate the IAM instance profile with your previously created EC2 instance. Back in *AWS Console > EC2*, select your instance and then *Actions > Security > Modify IAM role*. Select the IAM instance profile you just created. (It will be named "CodeDeployDemo-EC2-Instance-Profile" if the instructions haven't changed and you followed them exactly.)

In *AWS Console > CodeDeploy*, select *Deploy > Applications* and then *Create application*. Give it the *Application name* "flask_app" and select "EC2/On-premises" as the *Compute platform*. Create the application, then *Create deployment group*. Use the following settings:

- Name: servers 
- Service role: The one you created just a bit ago. ("CodeDeployServiceRole" if you followed the instructions from AWS.) 
- Deployment type: In-place
- Environment configuration: Amazon EC2 instances
    - Tag group 1: The tag you used for your instnace-- "flask_app_deploy_target" = "true"
    - After setting the tags, *Matching instances* should should be "1 unique matched instance"
- Agent configuration with AWS Systems Manager: use defaults
- Deployment settings: use defaults
- Load balancer: unselect Enable load balancing

Then *Create delployment group*. AWS CodeDeploy is now configured. On to AWS CodePipeline...

In *AWS Console > CodePipeline*, select *Pipeline > Pipelines* and then *Create pipeline*. Use the followoing settings:

- Pipeline name: flask_app
- Service role: New service role
- Role name: flask_app
- Artifact store: Default location
- Encryption key: Default AWS Managed Key

*Next*...

- Source provider: GitHub (Version 2)
- Connect to GitHub... follow the instructions to authenticate into your GitHub account and allow AWS CodePipeline to read from your repositories
- Repository name: Select the repository you created for flask_app
- Branch name: Select your main branch
- Change detection options: Start pipeline on code change = checked (so commits to your main branch will trigger a deployment)
- Output artifact format: CodePipeline default

*Next*...

*Skip build stage*

*Next*...

- Deploy provider: AWS CodeDeploy
- Region: Select the region your EC2 instance is in
- Application name: Select the application name you used in CodeDeploy ("flask_app")
- Deployment Group: Select the deployment group you added in CodeDeploy ("servers")

*Review*... *Create pipeline*

At this point, a deploy should start. You can see the progress in CodePipeline. After it completes ("Deploy" turns green and "Succeeded" is shown next to it), you can access the site in your browser -- http://{public IPv4 address}