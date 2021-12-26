#######################################################################################################
# ora_deploy_db_datapatch.sh
#
# Description: Run datapatch process for each database in data list
#              for a node
#
# Dependancies:  ora_deploy_db_datapatch.txt
#					node instance clusterdbname
#					node instance clusterdbname
#                All Instances for node must exist in the /etc/ortab for process to get ORACLE_HOME
#                The cluster dbname is the database name as identified in clusterware for RAC, if not present then assumes non-RAC
#                The Cluster dbname is important as it tends to be different between primary and standby clusters for database
#                as name in cluster tends to be same as DB unique name.
#
# Parameters:    file name for list of node/instances to run datapatch for
#                if not using default file name listed in dependancies
#
# Output:  <Script location on file system>/logs/ora_deploy_db_datapatch_<date>.log
#
# Execution:   From central deploy/monitor node
#				/u01/app/oracle/scripts/ora_deploy_db_datapatch.sh
#				or
#				/u01/app/oracle/scripts/ora_deploy_db_datapatch.sh <filename>
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
export PAGE_LIST=dbas@availity.com,dbas@realmed.com
export EMAIL_LIST=DBAs@availity.com

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
   
   ###############################################################################################################################
   # Status of instance and set to what we need instance state to be if currently running we must stop all instances of database
   export instance_running=`ssh -n ${nodename} "ps -ef | grep ora_smon_${instname} | grep -v grep"`
   
   if [ -z ${instance_running} ]
    then
      echo "Instance ${instname} on ${nodename} is not running can continue"
	  echo "Instance ${instname} on ${nodename} is not running can continue" >> ${LOG}
   else 
      echo "Instance ${instname} on ${nodename} is currently running, must shut down database across cluster before datapatch can be executed"
	  echo "Instance ${instname} on ${nodename} is currently running, must shut down database across cluster before datapatch can be executed" >> ${LOG}
	  
	  if [ -z ${racdbname} ]
	   then
	     echo "Shutting down non-RAC instance ${instname} on ${nodename}"
		 echo "Shutting down non-RAC instance ${instname} on ${nodename}" >> ${LOG}
		 export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo 'shutdown immediate' | ${ORACLE_HOME}/bin/sqlplus '/ as sysdba'"
		 ssh -n ${nodename} ${cmd} >> ${LOG}
		 
		# Check execution of instance/db state was successful
        if [ $? -eq 0 ]; then
           echo "Oracle instance ${instname} on ${nodename} is shutdown, continuing"
           echo "Oracle instance ${instname} on ${nodename} is sutdown, continuing" >> ${LOG}
        else
           echo "Oracle instance ${instname} on ${nodename} did not shutdown, aborting process"
           echo "Oracle instance ${instname} on ${nodename} did not shutdown, aborting process" >> ${LOG}
           exit 8
		fi
      else 
	     echo "Shutting down RAC database for ${instname} on ${nodename} for ${racdbname}"
		 echo "Shutting down RAC database for ${instname} on ${nodename} for ${racdbname}" >> ${LOG}
	     export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; ${ORACLE_HOME}/bin/srvctl stop database -d ${racdbname}" 
		 ssh -n ${nodename} ${cmd} >> ${LOG}
		 
		# Check execution of instance/db state was successful
        if [ $? -eq 0 ]; then
           echo "Oracle instance ${instname} on ${nodename} for ${racdbname} is shutdown, continuing"
           echo "Oracle instance ${instname} on ${nodename} for ${racdbname} is shutdown, continuing" >> ${LOG}
        else
           echo "Oracle instance ${instname} on ${nodename} for ${racdbname} did not shutdown, aborting process"
           echo "Oracle instance ${instname} on ${nodename} for ${racdbname} did not shutdown, aborting process" >> ${LOG}
           exit 8
		fi
	  fi
   fi
   
   #################################################################
   # Set instance state and upgrade mode to run datapatch
   echo "Processing database instance ${instname} for Upgrade Mode"
   echo "Processing database instance ${instname} for Upgrade Mode" >> ${LOG}

   echo "--" >> ${LOG}
   echo "Startup mount for ${instname} on ${nodename}"
   echo "Startup mount for ${instname} on ${nodename}" >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo 'startup mount' | $ORACLE_HOME/bin/sqlplus '/ AS SYSDBA'"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of Startup mount
   if [ $? -eq 0 ]; then
      echo "Startup Mount for ${instname} on ${nodename} ok, continuing"
      echo "Startup Mount for ${instname} on ${nodename} ok, continuing" >> ${LOG}
   else
      echo "Startup Mount for ${instname} on ${nodename} not ok, aborting process"
      echo "Startup Mount for ${instname} on ${nodename} not ok, aborting process" >> ${LOG}
      exit 8
   fi
   
   echo "--" >> ${LOG}
   echo "Alter System to turn off cluster_database for ${instname} on ${nodename}"
   echo "Alter System to turn off cluster_database for ${instname} on ${nodename}" >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo \"alter system set cluster_database=false scope=spfile sid='*' ;\"  | $ORACLE_HOME/bin/sqlplus '/ AS SYSDBA'"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of cluster_database false
   if [ $? -eq 0 ]; then
      echo "Cluster Database FALSE for ${instname} on ${nodename} ok, continuing"
      echo "Cluster Database FALSE for ${instname} on ${nodename} ok, continuing" >> ${LOG}
   else
      echo "Cluster Database FALSE for ${instname} on ${nodename} not ok, aborting process"
      echo "Cluster Database FALSE for ${instname} on ${nodename} not ok, aborting process" >> ${LOG}
      exit 8
   fi
   
   echo "--" >> ${LOG}
   echo "Shutdown for ${instname} on ${nodename}"
   echo "Shutdown for ${instname} on ${nodename}" >> ${LOG}   
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo 'shutdown immediate' | $ORACLE_HOME/bin/sqlplus '/ AS SYSDBA'"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of Shutdown
   if [ $? -eq 0 ]; then
      echo "Shutdown for ${instname} on ${nodename} ok, continuing"
      echo "Shutdown for ${instname} on ${nodename} ok, continuing" >> ${LOG}
   else
      echo "Shutdown for ${instname} on ${nodename} not ok, aborting process"
      echo "Shutdown for ${instname} on ${nodename} not ok, aborting process" >> ${LOG}
      exit 8
   fi

   echo "--" >> ${LOG}
   echo "Startup mount for ${instname} on ${nodename}"
   echo "Startup mount for ${instname} on ${nodename}" >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo 'startup mount' | $ORACLE_HOME/bin/sqlplus '/ AS SYSDBA'"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of Startup mount
   if [ $? -eq 0 ]; then
      echo "Startup Mount for ${instname} on ${nodename} ok, continuing"
      echo "Startup Mount for ${instname} on ${nodename} ok, continuing" >> ${LOG}
   else
      echo "Startup Mount for ${instname} on ${nodename} not ok, aborting process"
      echo "Startup Mount for ${instname} on ${nodename} not ok, aborting process" >> ${LOG}
      exit 8
   fi

   echo "--" >> ${LOG}
   echo "Open Wallet for ${instname} on ${nodename}"
   echo "Open Wallet for ${instname} on ${nodename}" >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo 'alter system set encryption wallet open identified by \"AllN1ghtL0ng\" ;' | $ORACLE_HOME/bin/sqlplus '/ AS SYSDBA'"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of Open Wallet
   if [ $? -eq 0 ]; then
      echo "Open Wallet for ${instname} on ${nodename} ok, continuing"
      echo "Open Wallet for ${instname} on ${nodename} ok, continuing" >> ${LOG}
   else
      echo "Open Wallet for ${instname} on ${nodename} not ok, aborting process"
      echo "Open Wallet for ${instname} on ${nodename} not ok, aborting process" >> ${LOG}
      exit 8
   fi
   
   echo "--" >> ${LOG}
   echo "Open Database Upgrade for ${instname} on ${nodename}"
   echo "Open Database Upgrade for ${instname} on ${nodename}" >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo 'alter database open upgrade ;' | $ORACLE_HOME/bin/sqlplus '/ AS SYSDBA'"
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
   # Check execution of Open Upgrade
   if [ $? -eq 0 ]; then
      echo "Oracle instance ${instname} on ${nodename} is in upgrade state, continuing"
      echo "Oracle instance ${instname} on ${nodename} is in upgrade state, continuing" >> ${LOG}
   else
      echo "Oracle instance ${instname} on ${nodename} is not in upgrade state, aborting process"
      echo "Oracle instance ${instname} on ${nodename} is not in upgrade state, aborting process" >> ${LOG}
      exit 8
   fi
  
   # If there is a custom glogin.sql that must be moved out of the way for datapatch -verbose execution or it will fail
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save"
   ssh -n ${nodename} ${cmd} >> ${LOG}
 
   # Execute the datapatch
   echo "Running datapatch for ${instname} on ${nodename}"
   echo "Running datapatch for ${instname} on ${nodename}" >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; $ORACLE_HOME/OPatch/datapatch -verbose"
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
   
   # Alter database back to RAC if RAC instance
   if [ -z ${racdbname} ]
	then
	  echo "non-RAC instance ${instname} on ${nodename} no need to update cluster_database setting"
      echo "non-RAC instance ${instname} on ${nodename} no need to update cluser_database setting" >> ${LOG}
   else 
      echo "--" >> ${LOG}
      echo "Alter System to turn on cluster_database for ${instname} on ${nodename}"
      echo "Alter System to turn on cluster_database for ${instname} on ${nodename}" >> ${LOG}
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo \"alter system set cluster_database=true scope=spfile sid='*' ;\"  | $ORACLE_HOME/bin/sqlplus '/ AS SYSDBA'"
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check execution of cluster_database false
      if [ $? -eq 0 ]; then
         echo "Cluster Database FALSE for ${instname} on ${nodename} ok, continuing"
         echo "Cluster Database FALSE for ${instname} on ${nodename} ok, continuing" >> ${LOG}
      else
         echo "Cluster Database FALSE for ${instname} on ${nodename} not ok, aborting process"
         echo "Cluster Database FALSE for ${instname} on ${nodename} not ok, aborting process" >> ${LOG}
         exit 8
      fi
   fi
   
   # Shutdown imstance so we can open it back up normal post datapatch
   echo "--" >> ${LOG}
   echo "Shutdown for ${instname} on ${nodename}"
   echo "Shutdown for ${instname} on ${nodename}" >> ${LOG}   
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo 'shutdown immediate' | $ORACLE_HOME/bin/sqlplus '/ AS SYSDBA'"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of Shutdown
   if [ $? -eq 0 ]; then
      echo "Shutdown for ${instname} on ${nodename} ok, continuing"
      echo "Shutdown for ${instname} on ${nodename} ok, continuing" >> ${LOG}
   else
      echo "Shutdown for ${instname} on ${nodename} not ok, aborting process"
      echo "Shutdown for ${instname} on ${nodename} not ok, aborting process" >> ${LOG}
      exit 8
   fi
   
   # Restart the database normal post datapatch execution
   if [ -z ${racdbname} ]
    then
      echo "Starting normal non-RAC instance ${instname} on ${nodename}"
      echo "Starting normal non-RAC instance ${instname} on ${nodename}" >> ${LOG}
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo 'startup' | ${ORACLE_HOME}/bin/sqlplus '/ as sysdba'" 
      ssh -n ${nodename} ${cmd} >> ${LOG}
		 
      # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "Oracle instance ${instname} on ${nodename} is started, continuing"
         echo "Oracle instance ${instname} on ${nodename} is started, continuing" >> ${LOG}
      else
         echo "Oracle instance ${instname} on ${nodename} did not start, aborting process"
         echo "Oracle instance ${instname} on ${nodename} did not start, aborting process" >> ${LOG}
         exit 8
      fi
   else 
	  echo "Starting normal RAC database ${racdbname} - ${instname} on ${nodename}"
      echo "Starting normal RAC instance ${racdbname} - ${instname} on ${nodename}" >> ${LOG}
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; ${ORACLE_HOME}/bin/srvctl start database -d ${racdbname}" 
      ssh -n ${nodename} ${cmd} >> ${LOG}
		 
      # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "Oracle instance ${instname} on ${nodename} started, continuing"
         echo "Oracle instance ${instname} on ${nodename} started, continuing" >> ${LOG}
      else
         echo "Oracle instance ${instname} on ${nodename} did not start, aborting process"
         echo "Oracle instance ${instname} on ${nodename} did not start, aborting process" >> ${LOG}
         exit 8
      fi
   fi   

   # If there is a custom glogin.sql that must be moved out of the way for datapatch -verbose execution or it will fail
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save ${ORACLE_HOME}/sqlplus/admin/glogin.sql"
   ssh -n ${nodename} ${cmd} >> ${LOG}
done < "${inputfile}"

echo "Datapatch for all nodes/instances in list from ${inpufile} successful."

exit 0
