#!/bin/bash

REPO_URL="https://example.com:XXXX/svn/repoName"
LOGIN="example" 
TARGET_DIR="folderName"
NEW=true

GITLAB_API_URL="http://XXX.XXX.XXX.XXX/api/v4"
GITLAB_TOKEN=$(<GITLAB_TOKEN)  # a besoin que le fichier "GITLAB_TOKEN" 
                               #soit dans le même répertoire 

PROJECT_ID="0"  # ID du projet GitLab

# permet d'acquérir l'id du projet, ne devrait jamais changer
#curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/interne%2FgitRepoName"

start=$(date +%s)

timestamp=$(date +"%Y%m%d_%H%M%S")
logfile="svn_to_git_$timestamp.log"
exec > >(tee "$logfile") 2>&1

# installation des packages nécessaires
sudo apt-get install git
sudo apt-get install git-svn
sudo apt-get install jq

read -p "Voulez vous importer vindlissvn ou un autre repo ? (o)ui - (a)autre: " TEMP
if [[ $TEMP == "a" ]]; then # si autre repo que vindilis
    NEW=false #NEW est une variable spécifique pour vindilis donc on la désactive
    read -p "URL du repo SVN: " REPO_URL
    TARGET_DIR="repo_git"
    
fi

read -p "Identifiant de connection au repo SVN  (prenom.nom): " LOGIN

# Si le dossier n'existe pas, on clone depuis SVN
if [ ! -d "$TARGET_DIR" ]; then
    echo "Clonage complet du dépôt SVN, cela va prendre un temps certain..."
    git svn clone -s --quiet "$REPO_URL" "$TARGET_DIR" --username="$LOGIN" /dev/null/

else # le dossier existe déjà, on met à jour
    NEW=false
    
    echo "Le dossier $TARGET_DIR existe déjà, mise à jour du dépôt..."
    cd "$TARGET_DIR" || { echo "Erreur : impossible de cd dans $TARGET_DIR"; exit 1; }

    echo "Récupération des changements SVN..."
    git svn rebase || { echo "Échec du rebase. Conflit ou problème réseau ?"; exit 1; }
    read -p "Quel est l'ID du repo Gitlab ? (Paramètre -> Général -> ID du projet) : " PROJECT_ID
    if [[ "$PROJECT_ID" == "0" ]]; then echo "Erreur, mauvais ID"; exit 1; fi
fi



# cd "$TARGET_DIR" || exit 1

echo "Mise à jour de SVN vers le repo Git déjà existant..."
git svn fetch || { echo "Échec du fetch depuis SVN."; exit 1; }


echo "TEMOIN_DEBUG_ligne59"

# CREATION BRANCHES
for ref in $(git for-each-ref --format='%(refname)' refs/remotes/origin/); do
    # Ignore les tags SVN
    if [[ "$ref" =~ ^refs/remotes/origin/tags/ ]]; then
        continue
    fi

    branch=$(echo "$ref" | sed 's#refs/remotes/origin/##')
    if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        git branch "$branch" "$ref"
        echo "Branche locale créée : $branch" 
    fi
done

echo "TEMOIN_DEBUG_ligne75"

echo "Récupération des tags SVN..."
# CREATION TAGS
for ref in $(git for-each-ref --format='%(refname)' refs/remotes/origin/tags); do
    tag=$(basename "$ref")
    if ! git rev-parse "refs/tags/$tag" >/dev/null 2>&1; then
        commit=$(git rev-parse "$ref^{commit}")
        git tag "$tag" "$commit"
        echo "Tag créé : $tag" 
    fi
done


#suppression des branches distantes utilisées pour les tags svn
for ref in $(git for-each-ref --format='%(refname)' refs/remotes/origin/tags); do
    git update-ref -d "$ref" 
    echo "Référence SVN supprimée : $ref" 
done


for tag in $(git tag); do
    tag_commit=$(git rev-parse "$tag")

    # Recherche d’un commit existant contenant le nom du tag (ex: v7.00.202)
    matching_commit=$(git log --all --grep="$tag" --format="%H" | grep -v "$tag_commit" | head -n1)

    if [ -n "$matching_commit" ]; then
        echo "Le tag $tag sera déplacé de $tag_commit vers $matching_commit" 
        git tag -d "$tag" 
        git tag "$tag" "$matching_commit"
    else
        echo "Aucun commit contenant '$tag' trouvé pour $tag, il est conservé tel quel." 
    fi
done

branches_identiques() {
    local branche1="$1"
    local branche2="$2"

    # Compare les deux branches
    if git diff --quiet "$branche1" "$branche2"; then
        # Pas de différence
        return 0
    else
        # Il y a une différence
        return 1
    fi
}

creer_merge_request() {
    local branche_source="$1"
    local branche_cible="$2"

    if [[ -z "$GITLAB_API_URL" || -z "$GITLAB_TOKEN" || -z "$PROJECT_ID" ]]; then
        echo "Erreur : GITLAB_API_URL, GITLAB_TOKEN ou PROJECT_ID non défini."
        return 1
    fi

    local titre="MR de $branche_source vers $branche_cible"
    local description="Merge request automatique créée depuis un script."

    curl --fail --request POST "${GITLAB_API_URL}/projects/${PROJECT_ID}/merge_requests" \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "{
            \"source_branch\": \"${branche_source}\",
            \"target_branch\": \"${branche_cible}\",
            \"title\": \"${titre}\",
            \"description\": \"${description}\"
        }"
    
    if [[ $? -eq 0 ]]; then
        echo "Merge request créée avec succès."
    else
        echo "Erreur lors de la création de la merge request."
        return 1
    fi
}


# compare les branches locales avec les branches en ligne
# et si y a une différence, crée un clone renommé de la 
# branche locale, la push, et fais une merge request avec
# la branche d'origine
traiter_branches_svn_vs_origin() {
for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        echo "→ Comparaison de $branch avec origin/$branch..."

        if branches_identiques "$branch" "origin/$branch"; then
            echo "Branche identique → rien à faire."
        else
            echo "Branche divergente → création d'une branche temporaire + MR"

            # Nouveau nom pour éviter les conflits
            temp_branch="auto-mr-$branch"

            # Supprime si elle existe déjà (éventuelle réexécution)
            git branch -D "$temp_branch" 2>/dev/null

            # Crée une copie
            git checkout "$branch"
            git checkout -b "$temp_branch"

            # Push la branche temporaire
            git push -u origin "$temp_branch"

            # Crée la merge request vers la branche d’origine
            creer_merge_request "$temp_branch" "$branch"
        fi
    else
        echo "→ Pas de branche distante origin/$branch. Push direct."
        git push -u origin "$branch"
    fi
done
}

# mise à jour du repo git
git fetch --prune origin || exit 1
traiter_branches_svn_vs_origin
git checkout master

# s'exécute uniquement si le repo cloné est vindilis segur, et si c'est la première fois
if [[ $NEW == "true" ]] && [[ $TEMP != "a" ]];  then
        if git show-ref --verify --quiet refs/heads/segur; then
        git checkout segur 
        if git show-ref --verify --quiet refs/heads/master; then
            if [ "$(git rev-parse segur)" != "$(git rev-parse master)" ]; then
                echo "La branche 'master' existait, différente de 'segur' → elle sera supprimée."
                git branch -D master 
            else

                echo "'master' et 'segur' pointent déjà sur le même commit, pas de suppression."
            fi
        fi
    fi
    echo "La branche 'segur' devient 'master'" 
    git branch -M segur master
fi

echo "Script terminé."

end=$(date +%s)
duration=$((end - start))
echo "Temps d'exécution : $duration secondes"



