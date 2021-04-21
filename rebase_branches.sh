#!/usr/bin/env bash

echo "TAG: $TAG"

IFS='
'
for x in `git branch -r | grep --invert-match master`;
do    
    branch="$(cut -d'/' -f2 <<<"$x")"
    echo $branch;

    git config --global user.email "kyle@bywatersolutions.com"
    git config --global user.name "Kyle M Hall"

    git checkout origin/$branch
    if [ $? -ne 0 ]; then
        echo "Checkout of origin/$branch failed: $?";
        exit 1;
    else
        echo "Checked out origin/$branch";
    fi

    git rebase origin/master
    if [ $? -ne 0 ]; then
        echo "Rebase of $branch failed: $?";
        exit 1;
    else
        echo "Rebased $branch";
    fi

    git push -f origin HEAD:$branch
    if [ $? -ne 0 ]; then
        echo "Push of $branch failed: $?";
        exit 1;
    else
        echo "Pushed $branch";
    fi

    if [ $TAG -ne "master" ]; then
        git tag $branch-$TAG
        git push origin $branch-$TAG
        if [ $? -ne 0 ]; then
            echo "Push of $branch failed: $?";
            exit 1;
        else
            echo "Pushed $branch";
        fi
    else
        echo "Not a tag, not pushing new tags"
    fi
done

git checkout origin/master
