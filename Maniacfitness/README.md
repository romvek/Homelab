# What is this?
[SparkyFitness](https://community-scripts.org/scripts/sparkyfitness) - A self-hosted, privacy-first alternative to MyFitnessPal. Track nutrition, exercise, body metrics, and health data while keeping full control of your data.

I found this on the Proxmox VE Scripts website.

# Why?
I have been wanting to move my health metrics/data to a self-hosted environment for a while now, primarily the metrics side of things. I want to visualize my stats to make them easier to read and see trends that I would typically have to pay premium prices for through apps like Strava.

# How to use
Run the following command from the proxmox shell. The installation is guided and creates the LXC during the process.

`bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/sparkyfitness.sh)"`
