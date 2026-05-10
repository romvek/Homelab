# *** This is in DEVELOPMENT *** 
Probably maybe don't use it yet

# What even is GLPI
[GLPI](https://www.glpi-project.org) (Gestionnaire Libre de Parc Informatique) is an open-source IT Asset Management (ITAM) and ITSM Service Desk solution.

# Why GLPI?
In a previous role GLPI was our chosen ticketing system solution. I researched, planned, installed, and configured GLPI. I configured the SSL certs, SSL config file, and the SMTP Oauth to hook into M365 so that GLPI can email ticket information and other notifications.

The only reason I am continuing to work on this project is just for the fact that I had wanted to automate the install process, which meant learning to code (or rather put code together), but still learning. It also meant learning Git and diving deeper into linux. 

# How to use me
Change the Configuration Variable values in the install script to match your desired setup
Run the command in your in your Container/VM
`wget -qO- https://raw.githubusercontent.com/romvek/Homelab/refs/heads/main/GLPI/glpi-install.sh | bash`

# Still to come
Working on making the script interactive
<img width="680" height="240" alt="image" src="https://github.com/user-attachments/assets/9d042e40-eb41-4d6a-a15c-ad3cca049828" />

`wget -qO- https://raw.githubusercontent.com/romvek/Homelab/refs/heads/main/GLPI/glpi-interactive-installer.sh | bash`
