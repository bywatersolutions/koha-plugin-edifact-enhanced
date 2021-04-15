#!/usr/bin/env bash

echo "TAG: $TAG"

IFS='
'
for x in `git branch -r | grep --invert-match master`;
do    
    branch="$(cut -d'/' -f2 <<<"$x")"
    echo $branch;

    git checkout github/$branch
    if [ $? -ne 0 ]; then
        echo "Checkout of github/$branch failed: $?";
        exit 1;
    else
        echo "Checked out github/$branch";
    fi

    git rebase github/master
    if [ $? -ne 0 ]; then
        echo "Rebase of $branch failed: $?";
        exit 1;
    else
        echo "Rebased $branch";
    fi

    git push -f github HEAD:$branch
    if [ $? -ne 0 ]; then
        echo "Push of $branch failed: $?";
        exit 1;
    else
        echo "Pushed $branch";
    fi

    git tag $branch-$TAG
    git push github $branch-$TAG
    if [ $? -ne 0 ]; then
        echo "Push of $branch failed: $?";
        exit 1;
    else
        echo "Pushed $branch";
    fi
done

git checkout github/master
