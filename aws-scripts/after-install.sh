# create venv and install required packages
cd /home/ubuntu/flask_app
python3 -m venv venv
venv/bin/pip3 install -r requirements.txt
# add soft link
if [ ! -h /var/www/html/flask_app ]; then
	sudo ln -sT /home/ubuntu/flask_app /var/www/html/flask_app
fi
# apache: enable site
sudo a2ensite flask_app
