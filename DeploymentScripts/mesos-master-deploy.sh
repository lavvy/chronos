#!/bin/bash
#mesos slave deployment script

MESOSRPM="http://downloads.mesosphere.io/master/centos/6/mesos_0.14.1_x86_64.rpm"
ZKBIN="http://apache.osuosl.org/zookeeper/zookeeper-3.4.5/zookeeper-3.4.5.tar.gz"
ZKPATH="/opt/zookeeper/"
MASTERCONFIGFILE="/etc/default/mesos-master"
MESOSINITFILE="/etc/init/mesos-master.conf"
MESOSSERVICENAME="mesos-master"



usage()
{
cat << EOF
usage: $0 options

This script will create mesos master setup with zookeeper chronos and  monit


OPTIONS:
   -h      Show this message
   -n      Mesos Clustername
EOF
}

NAME=
while getopts "hn:" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         n)
             NAME=$OPTARG
             ;;

         ?)
             usage
             exit
             ;;
     esac
done


if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

if [[ -z $NAME ]]
then

     usage
     exit 1
fi


#install dependancies
echo "installing java"
yum -y  install  java-1.7.0-openjdk-devel

echo "Installing Monit"
yum -y install monit
chkconfig monit on
cat <<END >/etc/monit.d/monitserver.conf
 set httpd port 2812 and
     allow 0.0.0.0/0.0.0.0 
      allow admin:ba6zisto read-only
END
service monit start

#install mesos rpm
echo "Downloding and installing mesos packages"
rpm -Uvh $MESOSRPM

if [ $? -eq 0 ]; then


#install zookeeper
echo "changing to install directory"
cd /tmp
echo "downloading zookeeper packages"
curl -sSfL $ZKBIN --output zookeeper.tar

echo "extracting zookeeper packages"
tar xf zookeeper.tar -C /opt/ --transform 's/zookeeper-3.4.5/zookeeper/' && cd 
echo "creating zookeeper config file"
cat <<END >/opt/zookeeper/conf/zoo.cfg
tickTime=2000
dataDir=/var/zookeeper
clientPort=2181
END

echo "creating zookeeper monit file"
cat <<END >/etc/monit.d/zookeeper.conf
check process zookeeper with pidfile /var/zookeeper/zookeeper_server.pid

start = "/opt/zookeeper/bin/zkServer.sh start"

stop = "/opt/zookeeper/bin/zkServer.sh stop"

END

monit reload
if [ $? -eq 0 ]; then
  echo "Monit  reloaded successfully"  

else
    echo "Error Reloading monit.Terminating Deployment"
    exit 1
fi



#create mesos config directory


echo "creating configuration file "
echo "using local zookeeper instalation"
#write config file
cat <<END >$MASTERCONFIGFILE
PORT=5050
ZK=`cat /etc/mesos/zk`
CLUSTER=$NAME
END


echo "creating init scripts"
cat <<END >$MESOSINITFILE
  description "mesos master"
       
       start on runlevel [2345]
       respawn
       
       script
       echo \$\$ > /var/run/mesos-master.pid
       exec /usr/bin/mesos-init-wrapper master
       end script


       post-stop script
       rm -f /var/run/mesos-master.pid
       end script

END


echo "setting up monit scripts"

cat <<END >/etc/monit.d/mesosmaster.conf
check process mesos_master with pidfile /var/run/mesos-master.pid

   
       start = "/sbin/initctl start mesos-master"

       stop = "/sbin/initctl stop mesos-master"

END

monit reload

if [ $? -eq 0 ]; then
  echo "MESOS MASTER started successfully" 
  echo "YOU can access MESOS web ui @ <IP address>:5050,make sure to configure firewall to allow access to port 5050"   
#setting up cronos
echo "installing cronos"
cd /opt/
echo "Downloding chronos packages"
curl -sSfL http://downloads.mesosphere.io/chronos/chronos-2.0.1_mesos-0.14.0-rc4.tgz --output chronos.tgz
tar xzf chronos.tgz && cd


echo "setting up init scripts"

cat <<END >/opt/mesos-deploy/chronos
#!/bin/bash


 case \$1 in
 start)


set -o errexit -o nounset -o pipefail

chronos_home="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" && cd .. && pwd -P )"
echo "Chronos home set to \$chronos_home"
export JAVA_LIBRARY_PATH="/usr/local/lib:/lib:/usr/lib"
export LD_LIBRARY_PATH="\${LD_LIBRARY_PATH:-/lib}"
export LD_LIBRARY_PATH="\$JAVA_LIBRARY_PATH:\$LD_LIBRARY_PATH"




heap=384m
       echo \$\$ > /var/run/chronos.pid;
       exec 2>&1 java -Xmx384m -Xms384m -cp /opt/chronos/target/chronos-2.0.1_mesos-0.14.0-rc4.jar com.airbnb.scheduler.Main --master zk://localhost:2181/mesos --zk_hosts zk://localhost:2181/mesos --hostname localhost.localdomain 1>/tmp/chronos.out
       ;;
     stop)
         kill \`cat /var/run/chronos.pid\` ;; 
     *)
 echo "usage: chronos {start|stop}" ;;
 esac
 exit 0
END
chmod 755 /opt/mesos-deploy/chronos
echo "setting up monit scripts"

cat <<END >/etc/monit.d/chronos.conf
check process chronos with pidfile /var/run/chronos.pid

       start = "/opt/mesos-deploy/chronos start"

       stop = "/opt/mesos-deploy/chronos stop"
END

monit reload
if [ $? -eq 0 ]; then
  echo "Monit Reloaded  successfully"  
   echo "Mesos Master setup completed successfully"  
  exit 0

else
    echo "Error Reloading monit"
    exit 1
fi


else
    echo "Error starting MESOSMASTER"
    exit 1
fi



else
    echo "Error installing mesos packages"
    exit 1
fi


