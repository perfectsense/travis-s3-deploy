#!/bin/bash

set -e -u

# Set the following environment variables:
# DEPLOY_BUCKET = your bucket name
# DEPLOY_BUCKET_PREFIX = a directory prefix within your bucket
# DEPLOY_BRANCHES = regex of branches to deploy; leave blank for all
# DEPLOY_EXTENSIONS = whitespace-separated file exentions to deploy; leave blank for "jar war zip"
# DEPLOY_FILES = whitespace-separated files to deploy; leave blank for $TRAVIS_BUILD_DIR/target/*.$extensions
# AWS_ACCESS_KEY_ID = AWS access ID
# AWS_SECRET_ACCESS_KEY = AWS secret
# AWS_SESSION_TOKEN = optional AWS session token for temp keys
# PURGE_OLDER_THAN_DAYS = Files in the .../deploy and .../pull-request prefixes in S3 older than this number of days will be deleted; leave blank for 90, 0 to disable.

if [[ -z "${DEPLOY_BUCKET}" ]]
then
    echo "Bucket not specified via \$DEPLOY_BUCKET"
fi

DEPLOY_BUCKET_PREFIX=${DEPLOY_BUCKET_PREFIX:-}

DEPLOY_BRANCHES=${DEPLOY_BRANCHES:-}

DEPLOY_EXTENSIONS=${DEPLOY_EXTENSIONS:-"jar war zip"}

DEPLOY_SOURCE_DIR=${DEPLOY_SOURCE_DIR:-$TRAVIS_BUILD_DIR/target}

PURGE_OLDER_THAN_DAYS=${PURGE_OLDER_THAN_DAYS:-"90"}

if [[ "$TRAVIS_PULL_REQUEST" != "false" ]]
then
    target_path=pull-request/$TRAVIS_PULL_REQUEST

elif [[ -z "$DEPLOY_BRANCHES" || "$TRAVIS_BRANCH" =~ "$DEPLOY_BRANCHES" ]]
then
    target_path=deploy/${TRAVIS_BRANCH////.}/$TRAVIS_BUILD_NUMBER

else
    echo "Not deploying."
    exit

fi

# BEGIN Travis fold/timer support

activity=""
timer_id=""
start_time=""

travis_start() {
    if [[ -n "$activity" ]]
    then
        echo "Nested travis_start is not supported!"
        return
    fi

    activity="$1"
    timer_id=$RANDOM
    start_time=$(date +%s%N)
    start_time=${start_time/N/000000000} # in case %N isn't supported

    echo "travis_fold:start:$activity"
    echo "travis_time:start:$timer_id"
}

travis_end() {
    if [[ -z "$activity" ]]
    then
        echo "Can't travis_end without travis_start!"
        return
    fi

    end_time=$(date +%s%N)
    end_time=${end_time/N/000000000} # in case %N isn't supported
    duration=$(expr $end_time - $start_time)
    echo "travis_time:end:$timer_id:start=$start_time,finish=$end_time,duration=$duration"
    echo "travis_fold:end:$activity"

    # reset
    activity=""
    timer_id=""
    start_time=""
}

# END Travis fold/timer support

discovered_files=""
for ext in ${DEPLOY_EXTENSIONS}
do
    discovered_files+=" $(ls $DEPLOY_SOURCE_DIR/*.${ext} 2>/dev/null || true)"
done

files=${DEPLOY_FILES:-$discovered_files}

if [[ -z "${files// }" ]]
then
    echo "Files not found; not deploying."
    exit
fi

target=builds/${DEPLOY_BUCKET_PREFIX}${DEPLOY_BUCKET_PREFIX:+/}$target_path/

if ! [ -x "$(command -v aws)" ]; then
    travis_start "pip"
    command -v pyenv && (pyenv global 3.7 || pyenv global 3.6 || true)
    pip install --upgrade --user -q awscli
    travis_end
    export PATH=~/.local/bin:$PATH
fi

travis_start "aws_rm"
aws s3api list-objects --bucket $DEPLOY_BUCKET --prefix $target --output=text | \
while read -r line
do
    filename=`echo "$line" | awk -F'\t' '{print $3}'`
    if [[ $filename != "" ]]
    then
        echo "Deleting existing artifact s3://$DEPLOY_BUCKET/$filename."
        aws s3 rm s3://$DEPLOY_BUCKET/$filename
    fi
done
travis_end

travis_start "aws_cp"
for file in $files
do
    aws s3 cp $file s3://$DEPLOY_BUCKET/$target
done
travis_end

if [[ $PURGE_OLDER_THAN_DAYS -ge 1 ]]
then
    travis_start "clean_s3"
    echo "Cleaning up builds in S3 older than $PURGE_OLDER_THAN_DAYS days . . ."

    cleanup_prefix=builds/${DEPLOY_BUCKET_PREFIX}${DEPLOY_BUCKET_PREFIX:+/}
    # TODO: this works with GNU date only
    older_than_ts=`date -d"-${PURGE_OLDER_THAN_DAYS} days" +%s`

    for suffix in deploy pull-request
    do
        # track number of items in the bucket to ensure we don't delete everything, which would break the _deploy servlet
        item_count=0
        echo "Getting number of items in $DEPLOY_BUCKET with prefix $cleanup_prefix$suffix/..."
        number_of_items=`aws s3api list-objects --bucket $DEPLOY_BUCKET --prefix $cleanup_prefix$suffix/ --output=json --query="length(Contents[])"` || number_of_items=0
        echo "$number_of_items"
        aws s3api list-objects --bucket $DEPLOY_BUCKET --prefix $cleanup_prefix$suffix/ --output=text | \
        while read -r line
        do
            last_modified=`echo "$line" | awk -F'\t' '{print $4}'`
            if [[ -z $last_modified ]]
            then
                continue
            fi
            ((item_count++))
            last_modified_ts=`date -d"$last_modified" +%s`
            filename=`echo "$line" | awk -F'\t' '{print $3}'`
            if [[ $last_modified_ts -lt $older_than_ts ]]
            then
                if [[ $filename != "" && "$item_count" -ne "$number_of_items" ]]
                then
                    echo "s3://$DEPLOY_BUCKET/$filename is older than $PURGE_OLDER_THAN_DAYS days ($last_modified). Deleting."
                    aws s3 rm "s3://$DEPLOY_BUCKET/$filename"
                elif [[ $filename != "" ]]
                then
                    echo "Skipping delete on s3://$DEPLOY_BUCKET/$filename to ensure at least one file in $DEPLOY_BUCKET."
                fi
            fi
        done
    done
    travis_end
fi

