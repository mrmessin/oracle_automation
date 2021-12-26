###############################################################################################################
#  Name: ora_deploy_ora_script.sh
#
# Description:  From central Monitoring server can execute
#               to deploy new script processes from software
#               location based on file with list of servers
#               deployment is for.
#
#  Parameters:  text file containing list of nodes to deploy scripts on
#               script name to deploy (optional)
#
#  Examples:    /u01/app/oracle/scripts/ora_deploy_ora_script.sh ora_deploy_nonprod_nodes.txt
#               /u01/app/oracle/scripts/ora_deploy_ora_script.sh ora_deploy_prod_nodes.txt ora_deploy_ora_script.sh
###############################################################################################################
#####################################################################
# Accept parameter of file the contains list of nodes to deploy for
#####################################################################
export inputfile=$1

######################################################################
# Accept optional peramter of script to deploy to nodes in file list
######################################################################
export deploy_script=$2

echo "Installing Oracle Script(s) on nodes in file ${inputfile}  ......."

echo "Checking List of Node File ${inputfile} Exists........"
if [ ! -f "$inputfile" ]

then
   echo "Install Failed -> ${inputfile} does not exist can not process installation."
   exit 8
fi

echo "Checking deploy script setting....."
if [ -z "${deploy_script}" ]; then
   # We did not specify a script to deploy so will deploy all scripts
   export deploy_script=*
   echo "Deploy script set to ${deploy_script}........."
else
   echo "Checking that deploy script ${deploy_script} exists......"
   if [ ! -f "${deploy_script}" ]
     then
       echo "Install Failed -> ${deploy_script} does not exist can not process installation."
       exit 8
   fi
fi

##################################################
# Standards Needed for Provision Script Process
##################################################
# Local hostname
export HOSTNAME=`hostname`

while read -r line
do
   export nodename=`echo ${line}`
   echo "Processing Scripts ${deploy_script} install on ${nodename}"

   scp ${deploy_script} ${nodename}:${deploy_script} >/dev/null
done < "${inputfile}"

exit 0
