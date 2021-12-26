#!/bin/bash
#
######################################################################################################
#   Name: ora_deploy_dr_test_end.sh
#
#
# Description:  Script to run through list of databases to take out of
#               mode for DR testing.
#
# Parameters:   file list of servers databases instances to utilize along with servcice at complete
#               <hostname> <db name> <db instance> <service,service,service> 
#
######################################################################################################
#
# Set the environment for the oracle account
. /home/oracle/.bash_profile

# Check that the correct
if (( $# != 1 ));then
  echo "Wrong number of arguments - must pass file name with host, db, db instance and services to take out of DR Test mode"
  exit 8
fi

#
# assign ORACLE_SID for local host, this will include the instance designation for Standby database
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
export LOGFILE=ora_deploy_dr_test_mode_end_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=dbas@availity.com,dbas@realmed.com
export EMAIL_LIST=DBAs@availity.com

echo "#################################################################################################"
echo "Using the Following Parameter Files:"
echo "Using the Following Parameter Files:" >> ${LOG}
echo "Node/db/dbinstance List File -> ${inputfile}"
echo "Node/db/dbinstance List File -> ${inputfile}" >> ${LOG}

# Loop through the file for putting into DR Mode
while read -r line
do
   ########################################################
   # Assign the nodename and agent home for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export dbname=`echo ${line}| awk '{print $2}'`
   export instname=`echo ${line}| awk '{print $3}'`
   export services=`echo ${line}| awk '{print $4}'`

   echo "Starting Database DR Test Mode End for ${dbname} and Services -> ${services}"
   echo "Starting Database DR Test Mode End for ${dbname} and Services -> ${services}" >> ${LOG}
   echo "--"
   echo "--" >> ${LOG}

   #########################################################################################
   # Set dbhome for instance on node 
   echo "Getting ORACLE_HOME for Database -> ${nodename} - ${dbname} - ${instname}...." 
   echo "Getting ORACLE_HOME for Database -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
   echo "--"
   echo "--" >> ${LOG}
   export cmd="/usr/local/bin/dbhome ${instname}"
   export ORACLE_HOME=`ssh -n ${nodename} ${cmd} `

   # Check ORACLE_HOME is set
   if [ $? -eq 0 ]; then
      echo "Oracle HOME for ${nodename} - ${instname} is ${ORACLE_HOME}"
      echo "Oracle HOME for ${nodename} - ${instname} is ${ORACLE_HOME}" >> ${LOG}
   else
      echo "Oracle HOME for ${nodename} - ${instname} could not be determined, aborting process"
      echo "Oracle HOME for ${nodename} - ${instname} could not be determined, aborting process" >> ${LOG}
      exit 8
   fi

   # Show the ORACLE_HOME value we got.
   echo "ORACLE_HOME for Database -> ${nodename} - ${dbname} - ${instname} -> ${ORACLE_HOME} ...." 
   echo "ORACLE_HOME for Database -> ${nodename} - ${dbname} - ${instname} -> ${ORACLE_HOME} ...." >> ${LOG}
   echo "--"
   echo "--" >> ${LOG}

   #########################################################################################
   # Check database is in snapshot standby before we start to convert back
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set feedback off\n set head off\n set pagesize 0\n select database_role from v\$database;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
   export result=`ssh -n ${nodename} ${cmd} `
   #echo "${result}" >> ${LOG}

   if [ "${result}" != "SNAPSHOT STANDBY" ]
    then
       echo "Database Instance ${dbinst} on ${nodename} is not in Snapshot Standby Mode, can not continue with DR Test Mode End, Skipping database"
       echo "Database Instance ${dbinst} on ${nodename} is not in Snapshot Standby Mode, can not continue with DR Test Mode End, Skipping database" >> ${LOG}
   else
      echo "Database Instance ${instname} on ${nodename} in Snapshot Standby Mode......"
      echo "Database Instance ${instname} on ${nodename} in Snapshot Standby Mode......" >> ${LOG}
   
      #########################################################
      # Completely shutdown the standby database this will allow us to control going into snapshot standby mode
      echo "Shutting Down Database -> ${nodename} - ${dbname} - ${instname}...." 
      echo "Shutting Down Database -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; export DBNAME=${dbname}; ${ORACLE_HOME}/bin/srvctl stop database -d ${dbname}"
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check execution of shutdown ok
      if [ $? -eq 0 ]; then
         echo "Shutdown on ${nodename} for Database ${dbname} was successful."
         echo "Shutdown on ${nodename} for Database ${dbname} was successful." >> ${LOG}
      else
         echo "Shutdown on ${nodename} for Database ${dbname} was not successful."
         echo "Shutdown on ${nodename} for Database ${dbname} was not successful." >> ${LOG}
         exit 8
      fi
   
      # If there is a custom glogin.sql that must be moved out of the way or it will fail
      echo "Handling glogin.sql on ${nodename}"
      echo "Handling glogin.sql on ${nodename}" >> ${LOG}
      export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save"
      ssh -n ${nodename} ${cmd} >> ${LOG}

      #########################################################
      # Start instance we are going to use to control going to snapshot standby 
      echo "Starting Standby Instance -> ${nodename} - ${dbname} - ${instname}...." 
      echo "Starting Standby Instance -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; export DBNAME=${dbname}; ${ORACLE_HOME}/bin/srvctl start instance -d ${dbname} -i ${instname} -o mount"
      ssh -n ${nodename} ${cmd}  >> ${LOG}

      # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "Instance Start on ${nodename} for instance ${instname} was successful."
         echo "Instance Start on ${nodename} for instance ${instname} was successful."  >> ${LOG}
      else
         echo "Instance Start on ${nodename} for instance ${instname} was not successful."
         echo "Instance Start on ${nodename} for instance ${instname} was not successful."  >> ${LOG}
         exit 8
      fi

      #########################################################
      # Convert Standby to Back to Physical Standby
      echo "Converting Snapshot Standby to Physical Standby -> ${nodename} - ${dbname} - ${instname}...." 
      echo "Converting Snapshot Standby to Physical Standby -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set head off\n set pagesize 0\n ALTER DATABASE CONVERT TO PHYSICAL STANDBY;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
      ssh -n ${nodename} ${cmd}  >> ${LOG}

      # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "Convert to Physical Standby on ${nodename} for instance ${instname} was successful."
         echo "Convert to Physical Standby on ${nodename} for instance ${instname} was successful."  >> ${LOG}
      else
         echo "Convert to Physical Standby on ${nodename} for instance ${instname} was not successful."
         echo "Convert to Physical Standby on ${nodename} for instance ${instname} was not successful."  >> ${LOG}
         exit 8
      fi

      #########################################################
      # Open all instances
      #
      # Assumes to be controlled by the database cluster configuration
      # Also assumes that clusterware controls if db should be open read only apply
      echo "Shutting Down Database -> ${nodename} - ${dbname} - ${instname}...."
      echo "Shutting Down Database -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; export DBNAME=${dbname}; ${ORACLE_HOME}/bin/srvctl stop database -d ${dbname}"
      ssh -n ${nodename} ${cmd}

      # Check execution of shutdown ok
      if [ $? -eq 0 ]; then
         echo "Shutdown on ${nodename} for Database ${dbname} was successful."
         echo "Shutdown on ${nodename} for Database ${dbname} was successful." >> ${LOG}
      else
         echo "Shutdown on ${nodename} for Database ${dbname} was not successful."
         echo "Shutdown on ${nodename} for Database ${dbname} was not successful." >> ${LOG}
         exit 8
      fi

      # Startup database with instances that are enabled
      echo "Startup Database -> ${nodename} - ${dbname} - ${instname}...."
      echo "Startup Database -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; export DBNAME=${dbname}; ${ORACLE_HOME}/bin/srvctl start database -d ${dbname}"
      ssh -n ${nodename} ${cmd}

      # Check execution of startup ok
      if [ $? -eq 0 ]; then
         echo "Startup Database on ${nodename} for Database ${dbname} was successful."
         echo "Startup Database on ${nodename} for Database ${dbname} was successful." >> ${LOG}
      else
         echo "Startup Database on ${nodename} for Database ${dbname} was not successful."
         echo "Startup Database on ${nodename} for Database ${dbname} was not successful." >> ${LOG}
         exit 8
      fi
 
      # Check if Now physical Standby Again
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set feedback off\n set head off\n set pagesize 0\n select database_role from v\$database;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
      export result=`ssh -n ${nodename} ${cmd} `
      #echo "${result}" >> ${LOG}
      #echo "${result}"

      if [ "${result}" != "PHYSICAL STANDBY" ]
       then
          echo "Database Instance ${dbinst} on ${nodename} is not in Physical Standby Mode, DR Test Mode End Failed."
          echo "Database Instance ${dbinst} on ${nodename} is not in Physical Standby Mode, DR Test Mode End Failed." >> ${LOG}
          exit 8
      fi
 
      # If not services supplied we can skip start services
      if [ "${services}" = "" ]
       then
         echo "No Services Defined to start Skipping Start Services......."
         echo "No Services Defined to start Skipping Start Services......." >> ${LOG}
      else
         #########################################################
         # Start services now that all instances are open
         echo "Starting Oracle services...."
         echo "Starting Oracle services...." >> ${LOG}
         export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; export DBNAME=${dbname}; ${ORACLE_HOME}/bin/srvctl start service -d ${dbname} -s ${services}"
         ssh -n ${nodename} ${cmd}

         # Check execution of start Services was successful
         if [ $? -eq 0 ]; then
            echo "Start Services -> ${services} on ${nodename} for db ${dbname} was successful."
            echo "Start Services -> ${services} on ${nodename} for db ${dbname} was successful."  >> ${LOG}
         else
            echo "Start Services -> ${services} on ${nodename} for db ${dbname} was not successful Please Check!."
            echo "Start Services -> ${services} on ${nodename} for db ${dbname} was not successful Please Check!."  >> ${LOG}
         fi
      fi

      #########################################################
      # Put glogin.sql back
      export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save ${ORACLE_HOME}/sqlplus/admin/glogin.sql"
      ssh -n ${nodename} ${cmd} >> ${LOG}
   fi

   echo "Completed DR Test Mode end for ${nodename} - ${dbname} - ${instname}"
   echo "Completed DR Test Mode end for ${nodename} - ${dbname} - ${instname}" >> ${LOG}
   echo "----------------------------------------------------------------------------------------------"
   echo "----------------------------------------------------------------------------------------------" >> ${LOG}
done < "${inputfile}"

echo "-"
echo "-" >> ${LOG}
echo "----------------------------------------------------------------------------------------------"
echo "----------------------------------------------------------------------------------------------" >> ${LOG}
echo "End DR Test Mode for all nodes/db/instances in list from ${inpufile} successful."
echo "End DR Test Mode for all nodes/db/instances in list from ${inpufile} successful." >> ${LOG}

# Mail Cron Run Log
/bin/mailx -s "End DR Test Mode for Oracle Standby Databases Completed" dba_team@availity.com <${LOG}

exit 0
