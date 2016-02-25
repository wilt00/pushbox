#!/usr/bin/env bash

# TODO:
# Get token, limit, browser, and last time run from config file - Done!
# Implement flags:
#  - Set limit manually - Done!
#  - Change config settings
#  - View all pushes rather than default only new pushes since last time
# Check for JSON.sh and download if necessary, setting chmod
# Implement 'marked read'

echo
echo Welcome to Pushbox! Now retrieving your pushes...
echo

usage(){
        echo 
        echo "Usage: pushbox.sh [-l] [-h]"
        echo "-l - Set limit. Return no more than this number of pushes. (May return fewer)"
        echo "-h - This help text."
        echo
        echo "Additional configuration settings can be set in:"
        echo "./pushbox.conf"
        echo "~/.config/pushbox.conf"
        echo "~/.pushbox.conf"
        echo "where later files take priority."
        echo
}

LIMIT="30"
MAX_LINE_LENGTH=50
DEFAULT_URL="https://www.pushbullet.com"
LASTRUN=""

source ./pushbox.conf
if [ -r ~/.config/pushbox.conf ]; then
        source ~/.config/pushbox.conf
fi
if [ -r ~/.pushbox.conf ]; then
        source ~/.pushbox.conf
fi





while getopts ":hl:" opt; do
        case $opt in
                h)
                        usage
                        exit 0
                        ;;
                l)
                        if ! [[ $OPTARG =~ ^[0-9]+$ ]]; then
                                echo "Invalid argument. -l should only be used with integer input." >&2
                                exit 1
                        fi
                        LIMIT="$OPTARG"
                        echo "Returning no more than $LIMIT pushes:"
                        echo 
                        ;;
                ?)
                        echo "Flag not recognized." >&2
                        exit 1
                        ;;
        esac
done


if [ -z "$TOKEN" ]; then
        echo "No access token set! Please specify an access token." >&2
        echo "Run \"pushbin.sh -h\" for more information."
        exit 1
fi
if [ -z "$BROWSER" ]; then
        echo "No default browser set! Please specify default browser." >&2
        echo "Run \"pushbin.sh -h\" for more information."
        exit 1
fi


IFS=$'\n'           # makes array only break on newline, not space
PUSHES=($(curl -s  \
        -u $TOKEN: \
        --data-urlencode active="true" \
        --data-urlencode limit=$LIMIT \
        --get "https://api.pushbullet.com/v2/pushes" \
        | ./JSON.sh -b -n
        ))
unset IFS


for PUSHLINE in "${PUSHES[@]}"; do
        
        if [[ $PUSHLINE != \[\"pushes* ]]; then continue; fi
        # ensures that non-push lines are not processed
        # one alternative is "cursor", at end when LIMIT exceeds something

        TEMP=${PUSHLINE:10}
        # Extracts a substring starting at character 10
        INDEX=${TEMP%%,*}
        # Removes all of string following first instance of double quote 
        # - this should leave a single integer value

        case $PUSHLINE in
                \[\"pushes\",[0-9]*,\"title\"\]* )
                       OUTPUT_TEXT[$INDEX]=${PUSHLINE#\[*\]}
#Removes 1st instance of [---] from front of PUSHLINE and adds to array
                       ;; 
                \[\"pushes\",[0-9]*,\"body\"\]* )
                       OUTPUT_TEXT[$INDEX]="${OUTPUT_TEXT[$INDEX]} ${PUSHLINE#\[*\]}"
#This is necessary for the rare case where a push has both title and body
                       ;; 
                \[\"pushes\",[0-9]*,\"url\"\]* )
                       TEMPURL=${PUSHLINE#\[*\]}
#Removes bracketed header
                       OUTPUT_URL[$INDEX]="${TEMPURL:2:-1}"
#Removes whitespace and quotation marks at beginning and end
                       ;;
                *)
                       continue
                       ;;
        esac

done
unset TEMP
unset TEMPURL

OUTPUT_COUNTER=0
TEXT_ARRLEN=${#OUTPUT_TEXT[@]}  # Length of text array
URL_ARRLEN=${#OUTPUT_URL[@]}    # Length of URL array
[[ $TEXT_ARRLEN -gt $URL_ARRLEN ]] && MAX_ARRLEN=$TEXT_ARRLEN || MAX_ARRLEN=$URL_ARRLEN

echo You have $MAX_ARRLEN unread pushes \(Pushes are not marked read automatically\)

if [[ $MAX_ARRLEN -eq 0 ]]; then
        echo Goodbye!
        exit 0
fi

echo

#for LINE in "${OUTPUT_TEXT[@]}"; do
while [[ $OUTPUT_COUNTER -lt $MAX_ARRLEN ]] ; do

        # If text is null, print url; if that's null, print error message
        if [[ -z ${OUTPUT_TEXT[$OUTPUT_COUNTER]} ]] ; then
                if [[ -z ${OUTPUT_URL[$OUTPUT_COUNTER]} ]] ; then
                        LINE="Empty push"
                else
                        LINE=${OUTPUT_URL[$OUTPUT_COUNTER]}
                fi
        else
                LINE=${OUTPUT_TEXT[$OUTPUT_COUNTER]}
        fi

        if [[ ${#LINE} -gt $MAX_LINE_LENGTH ]] ; then
                 echo $OUTPUT_COUNTER \) ${LINE:0:$[MAX_LINE_LENGTH - 3]}...
        else
                 echo $OUTPUT_COUNTER \) $LINE
        fi

        OUTPUT_COUNTER=$[OUTPUT_COUNTER + 1]
done

echo
echo q\) Quit now 
echo r\) Quit and mark as read
echo m\) Show more
echo
echo Type the number of the push you would like to open or another option.

read RESPONSE

case $RESPONSE in 
        [0-9]* )
                if [[ -z ${OUTPUT_URL[$RESPONSE]} ]]; then
                        $BROWSER $DEFAULT_URL
                else             
                        $BROWSER ${OUTPUT_URL[$RESPONSE]}
                fi
                ;;
        q)
                echo Goodbye!
                exit 0
                ;;
        r)
                echo Goodbye! \(Marking as read isn\'t implemented ye\t\)
                exit 0
                ;;
        *)
                echo That doesn\'t match any of the options
                ;;
esac
