#!/usr/bin/env bash

# TODO:
# Check for JSON.sh and download if necessary, setting chmod


# Default values
LIMIT="30"
MAX_LINE_LENGTH=50
DEFAULT_URL="https://www.pushbullet.com"
SENDING=0
SILENT=0
FAST_RETURN=0
NO_EXIT=0
CURSOR=""
PUSH_TYPE=""
PUSH_TITLE=""
PUSH_BODY=""
PUSH_URL=""

source ./pushbox.conf

if [ -r ~/.config/pushbox.conf ]; then
        source ~/.config/pushbox.conf
fi
if [ -r ~/.pushbox.conf ]; then
        source ~/.pushbox.conf
fi


usage () {
        echo 
        echo "Usage: pushbox.sh [OPTION]"
        echo
        echo "Display a list of Pushbullet pushes, or send a new push."
        echo
        echo "Options:"
        echo "-b [BODY] "$'\t'" - Send a push with BODY as its body text."
#        echo "-f [FILE] - Send a push and attach [FILE]." 
        echo "-h "$'\t'$'\t'" - Display this help text."
        echo "-l [NUMBER] "$'\t'" - Display no more than this number of pushes. "
        echo "-o "$'\t'$'\t'" - Immediately launch the most recent push."
        echo "-s "$'\t'$'\t'" - Silent mode. Suppresses all output text. Only used when sending pushes."
        echo "-t [TITLE] "$'\t'" - Send a push with TITLE as its title text."
        echo "-u [URL] "$'\t'" - Send a push with URL as its url."
        echo "-w [BROWSER]"$'\t'" - Open pushes using BROWSER."
        echo "-x "$'\t'$'\t'" - Do not immediately exit after opening push."
        echo
        echo "Note that as of Pushbullet API v2, the options -t and -b are functionally identical." 
        echo
        echo "Additional configuration settings can be set in:"
        echo "./pushbox.conf"
        echo "~/.config/pushbox.conf"
        echo "~/.pushbox.conf"
        echo "where later files take priority."
        echo
}

checkvars () {
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
}

send () {
        if [ $SILENT != 1 ] ; then
                echo "Sending push..."
        fi

        if [ -z $PUSH_TYPE ] ; then
                PUSH_TYPE="note"
        fi

        curl -s --header "Access-Token: $TOKEN" --header 'Content-Type: application/json' \
                --data-binary "{\"title\":\"$PUSH_TITLE\",\"body\":\"$PUSH_TEXT\",\"url\":\"$PUSH_URL\",\"type\":\"$PUSH_TYPE\"}" \
                --request POST \
                https://api.pushbullet.com/v2/pushes > /dev/null
        
        if [ $SILENT != 1 ] ; then
                echo "Push sent!"
                echo
        fi
}

get_pushes () {
        OLD_IFS=$IFS
        IFS=$'\n'           # makes array only break on newline, not space
        PUSHES=($(curl -s  \
                -u $TOKEN: \
                --data-urlencode active="true" \
                --data-urlencode limit=$LIMIT \
                --data-urlencode cursor=$CURSOR \
                --get "https://api.pushbullet.com/v2/pushes" \
                | ./JSON.sh -b -n
                ))
        IFS=$OLD_IFS

        for PUSHLINE in "${PUSHES[@]}"; do
                
                if [[ $PUSHLINE =~ \[\"pushes* ]] ; then
                    TEMPINDEX=${PUSHLINE:10}
                    # Extracts a substring starting at character 10
                    INDEX=${TEMPINDEX%%,*}
                    # Removes all of string following first instance of double quote 
                    # - this should leave a single integer value
                fi

                case $PUSHLINE in
                        \[\"cursor\"\]* )
                                TEMPCURSOR=${PUSHLINE#\[*\]}
                                CURSOR="${TEMPCURSOR:2:-1}"
                                ;;
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
                               ;;
                esac

        done
}

display_pushes () {
        OUTPUT_COUNTER=0
        TEXT_ARRLEN=${#OUTPUT_TEXT[@]}  # Length of text array
        URL_ARRLEN=${#OUTPUT_URL[@]}    # Length of URL array
        [[ $TEXT_ARRLEN -gt $URL_ARRLEN ]] && MAX_ARRLEN=$TEXT_ARRLEN || MAX_ARRLEN=$URL_ARRLEN
        # Use the larger value as the maximum array length


        if [[ $MAX_ARRLEN -eq 0 ]]; then
                echo "No more pushes to display. Goodbye!"
                exit 0
        fi

        echo

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
}

display_options () {
        echo
        echo m\) Show more
        echo q\) Quit 
        echo
        echo Type the number of the push you would like to open or another option.
}


while getopts ":hl:b:u:t:soxw:" opt; do
        case $opt in
                h)
                        usage
                        exit 0
                        ;;
                l)
                        if ! [[ $OPTARG =~ ^[0-9]+$ ]]; then
                                echo "Invalid argument: -l should only be used with integer input." >&2
                                exit 1
                        fi
                        LIMIT="$OPTARG" 
                        ;;
                b)
                        SENDING=1
                        PUSH_BODY=$OPTARG
                        ;;
                u)
                        if ! [ -z $PUSH_TYPE ] ; then
                                echo "Invalid input: cannot push url and file simultaneously." >&2
                        fi
                        URL_REGEX="(https?|ftp)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%?=~_|]"
                        if ! [[ $OPTARG =~ $URL_REGEX ]] ; then
                                echo "Invalid argument: input not formatted like url." >&2
                                exit 1
                        fi
                        SENDING=1 
                        PUSH_TYPE="link"
                        PUSH_URL=$OPTARG
                        ;;
                t)
                        SENDING=1
                        PUSH_TITLE=$OPTARG
                        ;;
                s)
                        SILENT=1
                        ;;
                o)
                        FAST_RETURN=1
                        ;;
                x)
                        NO_EXIT=1
                        ;;
                w)
                        CMDTYPE=$(type $OPTARG 2>&1 | grep -c "not found")
                        if [[ $CMDTYPE -eq 1 ]] ; then
                                echo "Invalid argument: input is not a valid shell command." >&2
                                exit 1
                        fi
                        BROWSER=$OPTARG
                        ;;
                ?)
                        echo "Flag not recognized." >&2
                        exit 1
                        ;;
        esac
done

checkvars

if [ $SENDING == 1 ] ; then
        send
        exit 0
fi

echo
echo "Welcome to Pushbox! Retrieving your pushes..."
echo

get_pushes

if [[ $FAST_RETURN -eq 1 ]] ; then
        $BROWSER ${OUTPUT_URL[0]} 
        exit 0
fi

display_pushes
display_options

while :
do
        read RESPONSE
        case $RESPONSE in 
                [0-9]* )
                        if [[ -z ${OUTPUT_URL[$RESPONSE]} ]]; then
                                $BROWSER $DEFAULT_URL
                        else             
                                $BROWSER ${OUTPUT_URL[$RESPONSE]}
                        fi
                        if ! [[ $NO_EXIT -eq 1 ]] ; then
                                exit 0
                        else
                                echo "What else would you like to do?"
                        fi
                        ;;
                q)
                        echo "Goodbye!"
                        exit 0
                        ;;
                m)
                        get_pushes
                        display_pushes
                        display_options
                        ;;
                *)
                        echo "That doesn\'t match any of the options"
                        display_options
                        ;;
        esac

done
