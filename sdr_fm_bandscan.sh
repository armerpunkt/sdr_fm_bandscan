#!/bin/bash

# Whether to use JQ to filter the RDS output
USE_JQ=${USE_JQ:-true}
# command to decode the FM signal, you can change it to whatever just
# use %freq% at the location to specify the frequency in MHz
FMCMD=${FMCMD:-"rtl_fm -M fm -l 0 -A fast -p 0 -s 171k -g 20 -F 9 -f %freq%M"}
# The above command will be pipped to the following command to
# decode the RDS from the FM output
if [[ $USE_JQ == true ]]; then
	RDSCMD=${RDSCMD:-"redsea | jq -r --unbuffered \".pi\""}
else
	RDSCMD=${RDSCMD:-"redsea"}
fi
# Command to log output to.
LOGCMD=${LOGCMD:-"echo \"%date%,%freq%,%picode%\" >> fm_bandscan.log"}
# Defaults to logging off
DO_LOG=${DO_LOG:-false}
# Wait this long before moving to the next frequency
TIMEOUT=${TIMEOUT:-30}
# Will stop checking after the PI Code is found and confirmed
# the following number of time (set to 0 to instantly stop)
LIMIT_CONFIRMS=${LIMIT_CONFIRMS:-3}
# Limit the bandscan to the following frequencies
# Defaults to ITU region 1
START_FREQ=${START_FREQ:-87.5}
END_FREQ=${END_FREQ:-107.9}

# Loop through the specified freqencies
for f in `seq $START_FREQ 0.2 $END_FREQ`;
do

	echo -n "Tuning: ${f}MHz "

	CURCMD="timeout ${TIMEOUT}s ${FMCMD/"%freq%"/"$f"} 2>/dev/null | ${RDSCMD}"
	CONFIRM=0

	# this will run the command at the end of the loop and
	# perform the following on each line of output as it comes in
	while read -r line
	do
		# Check if PI Code found
		if [[ $USE_JQ == true ]]; then
			[[ $line =~ ^0x([A-F0-9]{4})$ ]]
		else
			[[ $line =~ \"pi\":\"0x([A-F0-9]{4})\" ]]
		fi

		if [[ -z ${BASH_REMATCH[1]} ]]; then
			# If PI Code not found just output a dot
			echo -n "."
		else
			# If PI Code found output an x
			echo -n "x"

			# If no PI Code is set then set it
			if [[ -z "$PICODE" ]]; then
				PICODE=${BASH_REMATCH[1]}
			else
				# Otherwise check if it's the same
				if [ "$PICODE" = "${BASH_REMATCH[1]}" ]; then
					CONFIRM=$(($CONFIRM + 1))
					# If we get the desired number of confirmations stop early
					if [ $CONFIRM -ge $LIMIT_CONFIRMS ]; then
						break
					fi
				else
					# If it's different reset it and restart confirmations
					PICODE=${BASH_REMATCH[1]}
					CONFIRM=0
				fi
			fi
		fi
	done < <(eval "$CURCMD")

	# for some reason this continues before rtl_fm has fully finished
	# so wait for the process to actually end
	wait $!

	if [[ -z "$PICODE" ]]; then
		echo "(No PI Code Found)"
	else
		if [[ ${DO_LOG} == true ]]; then
			# Write output to log
			TMPCMD="${LOGCMD/"%freq%"/"$f"}"
			TMPCMD="${TMPCMD/"%picode%"/"$PICODE"}"
			CURDATE=`date -u +"%Y-%m-%dT%H:%M:%SZ"`
			TMPCMD="${TMPCMD/"%date%"/"$CURDATE"}"
			eval $TMPCMD
		fi
		echo " $PICODE"
		unset PICODE
	fi

done
