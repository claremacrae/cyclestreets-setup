# This file has to:
# Open a log file
# Go to the last line
# Work back finding 200 occurrences of calls to /api/journey.json
# Make an average of the last integers at the end of the line
# Convert to seconds

import subprocess, re

print "#\tStarting"

# Log file
logfile = "/websites/www/logs/veebee-access.log"

# Number of lines
lines = 4

# Api call pattern
apiCall = 'api/journey.json'

# Get the last few lines of the log file
p = subprocess.Popen(["tail", "-n" + str(lines), logfile], stdout=subprocess.PIPE)

# Read the data
line = p.stdout.readline()

# Number of matching lines
count = 0

# Total time
microSeconds = 0

# Scan
while line:
    print line
    line = p.stdout.readline()

    # Check if the line contains call to the journey api
    if apiCall in line:

        count += 1

        # Find the number at the end of the line
        match = re.match('.*?([0-9]+)$', line)
        if match:
            microSeconds += int(match.group(1))

# Time in millisconds
milliSeconds = 0

# Calculate the average
if count > 0:
    milliSeconds = (microSeconds / (count * 1000))
    

print "#\tStopping, counted: " + str(count) + " time: " + str(milliSeconds) + "ms."

# End of file
