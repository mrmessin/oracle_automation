#######################################################################################################
# ora_deploy_db_datapatch_rolling.sh
#
# Description: Run datapatch process for each database in data list
#              for a node
#
# Dependancies:  ora_deploy_db_datapatch.txt (or file passed is as parameter)
#					node instance clusterdbname
#					node instance clusterdbname
#                All Instances for node must exist in the /etc/ortab for process to get ORACLE_HOME
#                The cluster dbname is the database name as identified in clusterware for RAC, if not present then assumes non-RAC
#                The Cluster dbname is important as it tends to be different between primary and standby clusters for database
#                as name in cluster tends to be same as DB unique name.
#                The rolling will require non-use or very low use of the JAVAVM therefore must ensure services
#                Using JAVAVM are off or of low enough utization proces will not impact applications
#                Run on only one of the instances of all all instance homes are patched.
#                
# Is it Used, check all instances:
#     select count(*) from x$kglob where KGLOBTYP = 29 OR KGLOBTYP = 56;
# How much is it used:
#   select sess.service_name, sess.username,sess.program, count(*)
#   from
#   v$session sess,
#   dba_users usr,
#   x$kgllk lk,
#   x$kglob
#   where kgllkuse=saddr
#   and kgllkhdl=kglhdadr
#   and kglobtyp in (29,56)
#   and sess.user# = usr.user_id
#   and usr.oracle_maintained = 'N'      -- Omit 11.2.0.4
#   group by sess.service_name, sess.username, sess.program
#   order by sess.service_name, sess.username, sess.program;
#
# Parameters:    file name for list of node/instances to run datapatch for
#                if not using default file name listed in dependancies
#
# Output:  <Script location on file system>/logs/ora_deploy_db_datapatch_<date>.log
#
# Execution:   From central deploy/monitor node
#				/u01/app/oracle/scripts/ora_deploy_db_datapatch_rolling.sh
#				or
#				/u01/app/oracle/scripts/ora_deploy_db_datapatch_rolling.sh <filename>
#######################################################################################################
#
################################################################
# Accept parameter for file with list of nodes to work on
################################################################
export inputfile=$1

#####################################################
# Script environment
#####################################################
# assign a date we can use as part of the logfile
export DTE=`/bin/date +%m%d%C%y%H%M`

# Get locations
export SCRIPTLOC=`dirname $0`
export SCRIPTDIR=`basename $0`

# Set the logfile directory
export LOGPATH=${SCRIPTLOC}/logs
export LOGFILE=ora_deploy_db_datapatch_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables 
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=dbas@availity.com
export EMAIL_LIST=DBAs@availity.com

echo "----------------------------------------------------------------------------------------------"
echo "----------------------------------------------------------------------------------------------" >> ${LOG}
echo "Processing Parameters for Data Patch for Instances."
echo "Processing Parameters for Data Patch for Instances." > ${LOG}

################################################################
# Check Parameter was passed if not default to default filename
################################################################
if [ -z ${inputfile} ]
then
	echo "No node/instance list file provided defaulting to ${SCRIPTLOC}/ora_deploy_db_datapatch.txt"
	echo "No node/instance list file provided defaulting to ${SCRIPTLOC}/ora_deploy_db_datapatch.txt" >> ${LOG}
	export inputfile=${SCRIPTLOC}/ora_deploy_db_datapatch.txt
fi

################################################################
# Check Parameter is valid and file exists
################################################################
if [ ! -f "${inputfile}" ]
then
   echo "Node/instance list file provided -> ${inputfile} does not exist can not process upgrade."
   echo "Node/instance list file provided -> ${inputfile} does not exist can not process upgrade." >> ${LOG}
   exit 8
fi

# Set Local hostname
export HOSTNAME=`hostname`

echo "----------------------------------------------------------------------------------------------"
echo "----------------------------------------------------------------------------------------------" >> ${LOG}
echo "Running datapatch for each node/instance in ${inputfile}"
echo "Running datapatch for each node/instance in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}

# go through each node in the list in the file and execute upgrade
while read -r line
do
   ########################################################
   # Assign the nodename and agent home for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export instname=`echo ${line}| awk '{print $2}'`
   export racdbname=`echo ${line}| awk '{print $3}'`
   
   #########################################################################################
   # Set dbhome for instance on node and run datapatch from OPATCH location for instance
   export cmd="/usr/local/bin/dbhome ${instname}"
   export ORACLE_HOME=`ssh -n ${nodename} ${cmd}`
   
   # Check ORACLE_HOME is set
   if [ $? -eq 0 ]; then
      echo "Oracle HOME for ${nodename} - ${instname} is ${ORACLE_HOME}"
      echo "Oracle HOME for ${nodename} - ${instname} is ${ORACLE_HOME}" >> ${LOG}
   else
      echo "Oracle HOME for ${nodename} - ${instname} could not be determined, aborting process"
      echo "Oracle HOME for ${nodename} - ${instname} could not be determined, aborting process" >> ${LOG}
      exit 8
   fi
  
   ################################################################################################
   # Check if Database Instance is running, it needs to be running and open for process to work.
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set head off\n set pagesize 0\n select open_mode from v\$database;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'" 
   export result=`ssh -n ${nodename} ${cmd}` 
   #echo "|${result}|" >> ${LOG}

   if [ "${result}" != "READ WRITE" ]
    then
       echo "Database is not Open READ WRITE, can not continue with datapatch, exiting......"
       echo "Database is not Open READ WRITE, can not continue with datapatch, exiting......" >> ${LOG}
       exit 8
   fi
   
   echo "----------------------------------------------------------------------------------------------"
   echo "----------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Executing the Datapatch for ${instname} on ${nodename}"
   echo "Executing the Datapatch for ${instname} on ${nodename}" >> ${LOG}

   # If there is a custom glogin.sql that must be moved out of the way for datapatch -verbose execution or it will fail
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   ################################################################################################
   # Execute the datapatch
   echo "Running datapatch for ${instname} on ${nodename}"
   echo "Running datapatch for ${instname} on ${nodename}" >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; $ORACLE_HOME/OPatch/datapatch -verbose -skip_upgrade_check"
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
      # Check execution of instance/db state was successful
   if [ $? -eq 0 ]; then
      echo "datapatch on ${nodename} for instance ${instname} was successful." 
      echo "datapatch on ${nodename} for instance ${instname} was successful."  >> ${LOG}
   else
      echo "datapatch on ${nodename} for instance ${instname} was not successful." 
      echo "datapatch on ${nodename} for instance ${instname} was not successful."  >> ${LOG}
      exit 8
   fi 

   # If there is a custom glogin.sql that must be moved back in place
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save ${ORACLE_HOME}/sqlplus/admin/glogin.sql"
   ssh -n ${nodename} ${cmd} >> ${LOG}
done < "${inputfile}"

echo "################################################################################################"
echo "################################################################################################" >> ${LOG}
echo "Datapatch for all nodes/instances in list from ${inpufile} successful."
echo "Datapatch for all nodes/instances in list from ${inpufile} successful." >> ${LOG}

exit 0
