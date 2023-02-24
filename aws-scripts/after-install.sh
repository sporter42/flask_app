# create venv and install required packages
cd /home/ubuntu/flask_app
python3 -m venv venv
venv/bin/pip3 install -r requirements.txt
sudo a2ensite flask_app
