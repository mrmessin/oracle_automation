export nodelistfile=$1

#!/bin/ksh
clear
while read line; do
        echo "Checking ssh to: $line"
        /usr/bin/ssh -nq $line 'hostname' >>/dev/null
        if [ $? -eq 0 ]; then
         echo "ssh check to: $line is good"
         echo ""
        else
         echo "ssh check to: $line FAILED! "
         echo "Verify SSH keys! "
         echo""
        fi
done < ${nodelistfile}
