usage() 
{ echo "Usage: $0 -s <Subscription ID> [-g <Resource Group>] [-r azurerm_<resource_type>] [-x <yes|no(default)>] [-p <yes|no(default)>]" 1>&2; exit 1; 
}
x="no"
p="no"
while getopts ":s:g:r:x:p:" o; do
    case "${o}" in
        s)
            s=${OPTARG}
            ;;
        g)
            g=${OPTARG}
            ;;
        r)
            r=${OPTARG}
            ;;
        x)
            x="yes"
            ;;
        p)
            p="yes"
            ;;

        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${s}" ]; then
    usage
fi



export az2tfmess="# File auto generate by az2tf see https://github.com/andyt530/az2tf"
if [ "$s" != "" ]; then
    mysub=$s
else
    echo -n "Enter id of Subscription [$mysub] > "
    read response
    if [ -n "$response" ]; then
        mysub=$response
    fi
fi

echo "Checking Subscription $mysub exists ..."
isok="no"
subs=`az account list --query '[].id' | jq '.[]' | tr -d '"'`
for i in `echo $subs`
do
    if [ "$i" = "$mysub" ] ; then
        echo "Found subscription $mysub proceeding ..."
        isok="yes"
    fi
done
if [ "$isok" != "yes" ]; then
    echo "Could not find subscription with ID $mysub"
    exit
fi

myrg=$g
export ARM_SUBSCRIPTION_ID="$mysub"
az account set -s $mysub

mkdir -p tf.$mysub
cd tf.$mysub
rm -rf .terraform
rm -f import.log resources*.txt

../scripts/resources.sh 2>&1 | tee -a import.log
echo " "
echo "Subscription ID = ${s}"
echo "Azure Resource Group Filter = ${g}"
echo "Terraform Resource Type Filter = ${r}"
echo "Get Subscription Policies & RBAC = ${p}"
echo "Extract Key Vault Secrets to .tf files (insecure) = ${x}"
echo " "

#if [ "$2" != "" ]; then
#    myrg=$2
#    mkdir -p tf.${mysub}_${myrg}
#    cd tf.${mysub}_${myrg}
#    rm -rf .terraform
#    ../scripts/resources.sh $myrg
#else
#    mkdir -p tf.$mysub
#    cd tf.$mysub
#    rm -rf .terraform
#    ../scripts/resources.sh
#fi

pfx[1]="az group list"
res[1]="azurerm_resource_group"
pfx[2]="az lock list"
res[2]="azurerm_management_lock"

res[51]="azurerm_role_definition"
res[52]="azurerm_role_assignment"
res[53]="azurerm_policy_definition"
res[54]="azurerm_policy_assignment"

#
# uncomment following line if you want to use an SPN login
#../setup-env.sh

if [ "$g" != "" ]; then
    lcg=`echo $g | awk '{print tolower($0)}'`
    # check provided resource group exists in subscription
    exists=`az group exists -g $g`
    if  ! $exists ; then
        echo "Resource Group $g does not exists in subscription $mysub  Exit ....."
        exit
    fi
    echo "Filtering by Azure RG $g"
    grep $lcg resources2.txt > tmp.txt
    rm -f resources2.txt
    cp tmp.txt resources2.txt
    
fi

if [ "$r" != "" ]; then
    lcr=`echo $r | awk '{print tolower($0)}'`
    echo "Filtering by Terraform resource $lcr"
    grep $lcr resources2.txt > tmp2.txt
    rm -f resources2.txt
    cp tmp2.txt resources2.txt
fi


# cleanup from any previous runs
rm -f terraform*.backup
rm -f tf*.sh
cp ../stub/*.tf .
echo "terraform init" 
terraform init 2>&1 | tee -a import.log


# subscription level stuff - roles & policies
if [ "$p" = "yes" ]; then
    for j in `seq 51 54`; do
        docomm="../scripts/${res[$j]}.sh $mysub"
        echo $docomm
        eval $docomm 2>&1 | tee -a import.log
        if grep -q Error: import.log ; then
            echo "Error in log file exiting ...."
            exit
        fi
    done
fi


#echo $myrg
#../scripts/193_azurerm_application_gateway.sh $myrg

date
# top level stuff
j=1
if [ "$g" != "" ]; then
    trgs=`az group list --query "[?name=='$myrg']"`
else
    trgs=`az group list`
fi

count=`echo $trgs | jq '. | length'`
if [ "$count" -gt "0" ]; then
    count=`expr $count - 1`
    for i in `seq 0 $count`; do
        myrg=`echo $trgs | jq ".[(${i})].name" | tr -d '"'`
        echo -n $i of $count " "
        docomm="../scripts/${res[$j]}.sh $myrg"
        echo "$docomm"
        eval $docomm  2>&1 | tee -a import.log     
        if grep Error: import.log ; then
            echo "Error in log file exiting ...."
            exit
        fi
    done
fi
date
for j in `seq 2 2`; do
    c1=`echo ${pfx[${j}]}`
    gr=`printf "%s-" ${res[$j]}`
    #echo c1=$c1 gr=$gr
    comm=`printf "%s --query '[].resourceGroup' | jq '.[]' | sort -u" "$c1"`
    comm2=`printf "%s --query '[].resourceGroup' | jq '.[]' | sort -u | wc -l" "$c1"`
    #echo comm=$comm2
    tc=`eval $comm2`
    #echo tc=$tc
    tc=`echo $tc | tr -d ' '`
    trgs=`eval $comm`
    count=`echo ${#trgs}`
    if [ "$g" != "" ]; then
        ../scripts/${res[$j]}.sh $g
        else
        if [ "$count" -gt "0" ]; then
            c5="1"
            for j2 in `echo $trgs`; do
                echo -n "$c5 of $tc "
                docomm="../scripts/${res[$j]}.sh $j2"
                echo "$docomm"
                eval $docomm 2>&1 | tee -a import.log
                c5=`expr $c5 + 1`
                if grep -q Error: import.log ; then
                    echo "Error in log file exiting ...."
                    exit
                fi
            done
        fi
    fi   
done


echo loop through providers

for com in `ls ../scripts/*_azurerm*.sh | cut -d'/' -f3 | sort -g`; do   
        gr=`echo $com | awk -F 'azurerm_' '{print $2}' | awk -F '.sh' '{print $1}'`
        echo $gr
        lc="1"
        tc2=`cat resources2.txt | grep $gr | wc -l`
        for l in `cat resources2.txt | grep $gr` ; do
            echo -n $lc of $tc2 " "
            myrg=`echo $l | cut -d':' -f1`
            prov=`echo $l | cut -d':' -f2`
            #echo "debug $j prov=$prov  res=${res[$j]}"
            docomm="../scripts/$com $myrg"
            echo "$docomm"
            eval $docomm 2>&1 | tee -a import.log
            lc=`expr $lc + 1`
            if grep Error: import.log; then
                echo "Error in log file exiting ...."
                exit
            fi
        done
    rm -f terraform*.backup
done
date

if [ "$x" = "yes" ]; then
    echo "Attempting to extract secrets"
    ../scripts/350_key_vault_secret.sh 
fi


#
echo "Cleanup Cloud Shell"
rm -f *cloud-shell-storage*.tf
states=`terraform state list | grep cloud-shell-storage`
echo $states
terraform state rm $states
#
echo "Terraform Plan ..."
terraform plan .
exit
