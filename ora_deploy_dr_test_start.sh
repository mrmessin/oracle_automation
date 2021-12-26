#!/bin/bash
#
#####################################################################
#   Name: ora_deploy_dr_test_start.sh
#
#
# Description:  Script to run through list of databases to put into 
#               mode for DR testing.
#
# Parameters:   file list of servers databases instances to utilize and services at complete
#               <hostname> <db name> <db instance> <service,service,service>
#
#####################################################################
#
# Set the environment for the oracle account
. /home/oracle/.bash_profile

# Check that the correct
if (( $# != 1 ));then
  echo "ERROR -> Wrong number of arguments - must pass file name with host, db, db instance and services to put into DR test mode"
  exit 8
fi

#
# assign ORACLE_SID for local host, this will include the instance designation for Standby database
export inputfile=$1

#####################################################
# Check if input file passed and exists
#####################################################
if [ ! -f "${inputfile}" ]
then
   echo "ERROR -> ${inputfile} does not exist can not process installation."
   exit 8
fi

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
export LOGFILE=ora_deploy_dr_test_mode_start_${inputfile}_${DTE}.log
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

   echo "Starting DR Test Mode for ${dbname} with Services ${services}"
   echo "Starting DR Test Mode for ${dbname} with Services ${services}" >> ${LOG}
   echo "--"
   echo "--" >> ${LOG}

   #########################################################################################
   # Set dbhome for instance on node 
   echo "Getting ORACLE_HOME for Database -> ${nodename} - ${dbname} - ${instname}...." 
   echo "Getting ORACLE_HOME for Database -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
   export cmd="/usr/local/bin/dbhome ${instname}"
   export ORACLE_HOME=`ssh -n ${nodename} ${cmd} `

   # Check ORACLE_HOME is set
   if [ $? -eq 0 ]; then
      echo "Get Oracle HOME for ${nodename} - ${instname} is Determined." 
      echo "Get Oracle HOME for ${nodename} - ${instname} is Determined." >> ${LOG}
   else
      echo "ERROR -> Get Oracle HOME for ${nodename} - ${instname} could not be determined, aborting process"
      echo "ERROR -> Get Oracle HOME for ${nodename} - ${instname} could not be determined, aborting process" >> ${LOG}
      exit 8
   fi

   # Show the ORACLE_HOME value we got.
   echo "ORACLE_HOME for Database -> ${nodename} - ${dbname} - ${instname} -> ${ORACLE_HOME} ...." 
   echo "ORACLE_HOME for Database -> ${nodename} - ${dbname} - ${instname} -> ${ORACLE_HOME} ...." >> ${LOG}

   #########################################################################################
   # Check database is in physical standby before we start to convert 
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set feedback off\n set head off\n set pagesize 0\n select database_role from v\$database;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
   export result=`ssh -n ${nodename} ${cmd} `
   #echo "${result}" >> ${LOG}
   #echo "${result}"
                       
   if [ "${result}" != "PHYSICAL STANDBY" ]
    then
       echo "WARNING -> Database Instance $instname} on ${nodename} is not in Physical Standby Mode, Skipping Convert to Snapshot Standby"
       echo "WARNING -> Database Instance ${instname} on ${nodename} is not in Physical Standby Mode, Skipping Convert to Snapshot Standby" >> ${LOG}
   fi
   
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
      echo "ERROR -> Shutdown on ${nodename} for Database ${dbname} was not successful."
      echo "ERROR -> Shutdown on ${nodename} for Database ${dbname} was not successful." >> ${LOG}
      exit 8
   fi
   
   # If there is a custom glogin.sql that must be moved out of the way or it will fail
   echo "--"
   echo "--" 
   echo "Handling glogin.sql on ${nodename}"
   echo "Handling glogin.sql on ${nodename}" >> ${LOG}
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   #########################################################
   # Start instance we are going to use to control going to snapshot standby 
   echo "Starting Standby Instance -> ${nodename} - ${dbname} - ${instname}...." 
   echo "Starting Standby Instance -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; export DBNAME=${dbname}; ${ORACLE_HOME}/bin/srvctl start instance -d ${dbname} -i ${instname}"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of instance/db state was successful
   if [ $? -eq 0 ]; then
      echo "Instance Start on ${nodename} for instance ${instname} was successful."
      echo "Instance Start on ${nodename} for instance ${instname} was successful."  >> ${LOG}
   else
      echo "ERROR -> Instance Start on ${nodename} for instance ${instname} was not successful."
      echo "ERROR -> Instance Start on ${nodename} for instance ${instname} was not successful."  >> ${LOG}
      exit 8
   fi

   #########################################################
   # Stop the standby apply
   echo "Stopping Standby Apply -> ${nodename} - ${dbname} - ${instname}...." 
   echo "Stopping Standby Apply -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set head off\n set pagesize 0\n alter database recover managed standby database cancel;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of instance/db state was successful
   if [ $? -eq 0 ]; then
      echo "Cancel Managed Standby on ${nodename} for instance ${instname} was successful."
      echo "Cancel Managed Standby on ${nodename} for instance ${instname} was successful."  >> ${LOG}
   else
      echo "ERROR -> Cancel Managed Standby on ${nodename} for instance ${instname} was not successful."
      echo "ERROR -> Cancel Managed Standby on ${nodename} for instance ${instname} was not successful."  >> ${LOG}
      exit 8
   fi

   #########################################################
   # Convert Standby to snapshot Standby
   echo "Converting Standby to Snasphot Standby -> ${nodename} - ${dbname} - ${instname}...." 
   echo "Converting Standby to Snapshot Standby -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set head off\n set pagesize 0\n ALTER DATABASE CONVERT TO SNAPSHOT STANDBY;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of instance/db state was successful
   if [ $? -eq 0 ]; then
      echo "Convert to Snapshot Standby on ${nodename} for instance ${instname} was successful."
      echo "Convert to Snapshot Standby on ${nodename} for instance ${instname} was successful."  >> ${LOG}
   else
      echo "ERROR -> Convert to Snapshot Standby on ${nodename} for instance ${instname} was not successful."
      echo "ERROR -> Convert to Snapshot Standby on ${nodename} for instance ${instname} was not successful."  >> ${LOG}
      exit 8
   fi

   #########################################################
   # Verify that it is snapshot standby mode
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set feedback off\n set head off\n set pagesize 0\n select database_role from v\$database;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
   export result=`ssh -n ${nodename} ${cmd} `
   #echo "${result}" >> ${LOG}

   if [ "${result}" != "SNAPSHOT STANDBY" ]
    then
       echo "ERROR -> Database Instance ${instname} on ${nodename} is not in Snapshot Standby Mode, can not continue with DR Test Mode, exiting."
       echo "ERROR -> Database Instance ${instname} on ${nodename} is not in Snapshot Standby Mode, can not continue with DR Test Mode, exiting." >> ${LOG}
       exit 8
   else
       echo "Database Instance ${instname} on ${nodename} in Snapshot Standby Mode......"
       echo "Database Instance ${instname} on ${nodename} in Snapshot Standby Mode......" >> ${LOG}
   fi

   #########################################################
   # Opening snapshot Standby
   echo "Opening Snasphot Standby -> ${nodename} - ${dbname} - ${instname}...." 
   echo "Opening Snapshot Standby -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set head off\n set pagesize 0\n ALTER DATABASE OPEN;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of instance/db state was successful
   if [ $? -eq 0 ]; then
      echo "Opening Snapshot Standby on ${nodename} for instance ${instname} was successful."
      echo "Opening Snapshot Standby on ${nodename} for instance ${instname} was successful."  >> ${LOG}
   else
      echo "ERROR -> Opening Snapshot Standby on ${nodename} for instance ${instname} was not successful."
      echo "ERROR -> Opening Snapshot Standby on ${nodename} for instance ${instname} was not successful."  >> ${LOG}
      exit 8
   fi

   #########################################################
   # verify that the snapshot standby is open read write
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set feedback off\n set head off\n set pagesize 0\n select open_mode from v\$database;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
   export result=`ssh -n ${nodename} ${cmd} `
   #echo "${result}" >> ${LOG}

   if [ "${result}" != "READ WRITE" ]
    then
       echo "ERROR -> Database is not Open READ WRITE, can not continue with DR Test Mode, exiting skipping database......"
       echo "ERROR -> Database is not Open READ WRITE, can not continue with DR Test Mode, exiting skipping database......" >> ${LOG}
       exit 8
   else
       echo "Database Instance ${instname} on ${nodename} is Open READ WRITE......"
       echo "Database Instance ${instname} on ${nodename} is Open READ WRITE......" >> ${LOG}
   fi

   #########################################################
   # Open all instances if instance enabled can restart database to do this
   echo "Shutting Down Database -> ${nodename} - ${dbname} - ${instname}...."
   echo "Shutting Down Database -> ${nodename} - ${dbname} - ${instname}...." >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; export DBNAME=${dbname}; ${ORACLE_HOME}/bin/srvctl stop database -d ${dbname}"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of shutdown ok
   if [ $? -eq 0 ]; then
      echo "Shutdown for Database ${dbname} was successful."
      echo "Shutdown for Database ${dbname} was successful." >> ${LOG}
   else
      echo "ERROR -> Shutdown for Database ${dbname} was not successful."
      echo "ERROR -> Shutdown for Database ${dbname} was not successful." >> ${LOG}
      exit 8
   fi

   # Startup database with instances that are enabled
   echo "Startup Database All Configured Instances -> ${dbname}...."
   echo "Startup Database All Configured Instances -> ${dbname}...." >> ${LOG}
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; export DBNAME=${dbname}; $ORACLE_HOME/bin/srvctl start database -d ${dbname} -startoption open"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check execution of Startup ok
   if [ $? -eq 0 ]; then
      echo "Startup Database All Configured Instances for Database ${dbname} was successful."
      echo "Startup Database All Configured Instances for Database ${dbname} was successful." >> ${LOG}
   else
      echo "ERROR -> Startup Database All Configured Instances for Database ${dbname} was not successful."
      echo "ERROR -> Startup Database All Configured Instances for Database ${dbname} was not successful." >> ${LOG}
      exit 8
   fi

   #########################################################
   # Verify that it is snapshot standby mode
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set feedback off\n set head off\n set pagesize 0\n select database_role from v\$database;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
   export result=`ssh -n ${nodename} ${cmd} `
   #echo "${result}" >> ${LOG}

   if [ "${result}" != "SNAPSHOT STANDBY" ]
    then
       echo "ERROR -> Database Instance ${instname} on ${nodename} is not in Snapshot Standby Mode, can not continue with DR Test Mode, exiting."
       echo "ERROR -> Database Instance ${instname} on ${nodename} is not in Snapshot Standby Mode, can not continue with DR Test Mode, exiting." >> ${LOG}
       exit 8
   else
       echo "Database Instance ${instname} on ${nodename} in Snapshot Standby Mode......"
       echo "Database Instance ${instname} on ${nodename} in Snapshot Standby Mode......" >> ${LOG}
   fi

   #########################################################
   # verify that the snapshot standby is open read write
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set feedback off\n set head off\n set pagesize 0\n select open_mode from v\$database;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
   export result=`ssh -n ${nodename} ${cmd} `
   #echo "${result}" >> ${LOG}

   if [ "${result}" != "READ WRITE" ]
    then
       echo "ERROR -> Database is not Open READ WRITE, can not continue with DR Test Mode, exiting......"
       echo "ERROR -> Database is not Open READ WRITE, can not continue with DR Test Mode, exiting......" >> ${LOG}
       exit 8
   else
       echo "Database Instance ${instname} on ${nodename} is Open READ WRITE......"
       echo "Database Instance ${instname} on ${nodename} is Open READ WRITE......" >> ${LOG}
   fi

   if [ "${services}" = "" ]
    then
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; export DBNAME=${dbname}; ${ORACLE_HOME}/bin/srvctl start service -d ${dbname}"
      ssh -n ${nodename} ${cmd} >> ${LOG}
      
      # Check execution of start Services was successful
      if [ $? -eq 0 ]; then
         echo "Start Services -> ALL on ${nodename} for db ${dbname} was successful." 
         echo "Start Services -> ALL on ${nodename} for db ${dbname} was successful."  >> ${LOG}
      else
         echo "WARNING -> Start Services -> ALL on ${nodename} for db ${dbname} was not successful Please Check!." 
         echo "WARNING -> Start Services -> ALL on ${nodename} for db ${dbname} was not successful Please Check!."  >> ${LOG}
      fi
   else
      #########################################################
      # Start services now that all instances are open
      echo "Starting Oracle services...." 
      echo "Starting Oracle services...." >> ${LOG}
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; export DBNAME=${dbname}; ${ORACLE_HOME}/bin/srvctl start service -d ${dbname} -s ${services}"
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check execution of start Services was successful
      if [ $? -eq 0 ]; then
         echo "Start Services -> ${services} on ${nodename} for db ${dbname} was successful." 
         echo "Start Services -> ${services} on ${nodename} for db ${dbname} was successful."  >> ${LOG}
      else
         echo "WARNING -> Start Services -> ${services} on ${nodename} for db ${dbname} was not successful Please Check!." 
         echo "WARNING -> Start Services -> ${services} on ${nodename} for db ${dbname} was not successful Please Check!."  >> ${LOG}
      fi
   fi 

   #########################################################
   # Put glogin.sql back
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save ${ORACLE_HOME}/sqlplus/admin/glogin.sql"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   echo "Completed DR Test Mode start for ${nodename} - ${dbname} - ${instname}"
   echo "Completed DR Test Mode start for ${nodename} - ${dbname} - ${instname}" >> ${LOG}
   echo "----------------------------------------------------------------------------------------------"
   echo "----------------------------------------------------------------------------------------------" >> ${LOG}

   echo "Checking the scan name we want to use for service conenction checks!"
   echo "Checking the scan name we want to use for service conenction checks!" >> ${LOG}

   # determine scan name to use
   cmd="export ORACLE_HOME=${ORACLE_HOME}; ${ORACLE_HOME}/bin/srvctl config scan | grep \"SCAN name:\" | awk '{print \$3}' | tr -d ,"
   #echo ${cmd}
   export scan_name=`ssh -n ${nodename} ${cmd} `

   if [ "${scan_name}" = "" ]
    then
       echo "ERROR -> Could not get scan name can not check service connections."
       echo "ERROR -> Could not get scan name can not check service connections." >> ${LOG}
       exit 8
   else
      echo "Will Continue Checking Connections using scan name ${scan_name}."
      echo "Will Continue Checking Connections using scan name ${scan_name}." >> ${LOG}
   fi

   echo "----------------------------------------------------------------------------------------------"
   echo "----------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Will check that database connections using services are working."
   echo "Will check that database connections using services are working." >> ${LOG}


   #########################################################
   # set username and password for connection check user we can create user for test then drop user     
   export myuser=connection_check
   export mypassword=connection_check$31$checking

   # Create the user for test check

   #########################################################
   # List of all services loop through and check connection to database through each service
   # Report any service where connection fails to screen and log
   if [ "${services}" = "" ]
    then
      # Get list of services to loop through
      # Execute the command to list services based on parameter passed
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; $ORACLE_HOME/bin/srvctl config service -d ${dbname} | grep \"Service name:\" | awk '{print \$3}'"
      echo ${cmd}
      export servicelist=`ssh -n ${nodename} ${cmd} `
      echo "${servicelist}" >> ${LOG}

      if [ "${servicelist}" = "" ]
       then
         echo "WARNING -> No Services retrived from Service List Please Verify."
         echo "WARNING -> No Services retrived from Service List Please Verify." >> ${LOG}
      else 
 
         # Run connection for service 
         for thisservice in ${servicelist}
         do
            export cmd="sqlplus ${myuser}/${mypassword}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${scan_name})(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=${thisservice})))"
            ssh -n ${nodename} ${cmd} >> ${LOG}

            # Check execution of instance/db state was successful
            if [ $? -eq 0 ]; then
               echo "ERROR -> Connection Using Service ${thisservice} Failed."
               echo "ERROR -> Connection Using Service ${thisservice} Failed." >> ${LOG}
            else
               echo "Connection Using Service ${thisservice} OK."
               echo "Connection Using Service ${thisservice} OK." >> ${LOG}
            fi
         done 
      fi
   else
      # loop through services separate by ,
      for thisservice in $(echo ${services} | sed "s/,/ /g")
      do
         export cmd="sqlplus ${myuser}/${mypassword}@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${scan_name})(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=${thisservice})))"
         ssh -n ${nodename} ${cmd} >> ${LOG}

         # Check execution of instance/db state was successful
         if [ $? -eq 0 ]; then
            echo "Connection Using Service ${thisservice} OK."
            echo "Connection Using Service ${thisservice} OK." >> ${LOG}
         else
            echo "ERROR -> Connection Using Service ${thisservice} Failed."
            echo "ERROR -> Connection Using Service ${thisservice} Failed." >> ${LOG}
         fi
      done
   fi

   # Drop user created for Services login check

   #########################################################
   # If aries we have to truncate the work_queue table
   # Feature Add
   if [[ ${instname,,} == *"aries"* ]]; then
      echo "----------------------------------------------------------------------------------------------"
      echo "----------------------------------------------------------------------------------------------" >> ${LOG}
      echo "ARIES Database Truncating the work_queue and aggregation tables."
      echo "ARIES Database Truncating the work_queue and aggregation tables." >> ${LOG}

      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set echo off\n truncate table ariestech.work_queue; \n truncate table ariestech.aggregation;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
      ssh -n ${nodename} ${cmd} >> ${LOG}
      #echo "${result}" >> ${LOG}

      if [ $? -eq 0 ]
       then
          echo "ERROR -> Aries Truncate of work_queue and aggregation Failed......"
          echo "ERROR -> Aries Truncate of work_queue and aggregation Failed......" >> ${LOG}
      else
          echo "Aries Truncate of work_queue and aggregation OK......"
          echo "Aries Truncate of work_queue and aggregation OK......" >> ${LOG}
      fi
   fi
done < "${inputfile}"

echo "-"
echo "-" >> ${LOG}
echo "----------------------------------------------------------------------------------------------"
echo "----------------------------------------------------------------------------------------------" >> ${LOG}
echo "Start DR Test Mode for all nodes/db/instances in list from ${inpufile} successful."
echo "Start DR Test Mode for all nodes/db/instances in list from ${inpufile} successful." >> ${LOG}

# Mail Cron Run Log
/bin/mailx -s "Start DR Test Mode for Oracle Standby Databases Completed" dba_team@availity.com <${LOG}

exit 0
