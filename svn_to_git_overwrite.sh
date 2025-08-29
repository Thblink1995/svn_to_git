#!/bin/bash

# Le script marche si l'on suppose que l'architecture du repo SVN suit la norme (trunk / branches)

REPO_URL="https://example.com:XXXX/svn/monRepoSvn"
LOGIN="example" 
TARGET_DIR="nomDeDossier"
NEW=true

start=$(date +%s)

timestamp=$(date +"%Y%m%d_%H%M%S")
logfile="svn_to_git_$timestamp.log"
exec > >(tee "$logfile") 2>&1

# installation des packages nécessaires
sudo apt-get install git
sudo apt-get install git-svn
sudo apt-get install jq

read -p "Nom du dossier cible (existant ou à créer): " TARGET_DIR

# Si le dossier n'existe pas, on clone depuis SVN
if [ ! -d "$TARGET_DIR" ]; then
    
    read -p "URL du repo SVN: " REPO_URL
    read -p "Identifiant de connection au repo SVN  (prenom.nom): " LOGIN

    echo "Clonage complet du dépôt SVN, cela va prendre un temps certain..."
    git svn clone -s --quiet "$REPO_URL" "$TARGET_DIR" --username="$LOGIN" /dev/null/

else # le dossier existe déjà, on met à jour
    NEW=false
    
    echo "Le dossier $TARGET_DIR existe déjà, mise à jour du dépôt..."
    cd "$TARGET_DIR" || { echo "Erreur : impossible de cd dans $TARGET_DIR"; exit 1; }

    echo "Récupération des changements SVN..."
    git svn rebase || { echo "Échec du rebase. Conflit ou problème réseau ?"; exit 1; }
    git push origin
fi

cd "$TARGET_DIR" || { echo "Echec: impossible de trouver le dossier $TARGET_DIR"; exit 1; }

echo "Mise à jour de SVN vers le repo Git déjà existant..."
git svn fetch || { echo "Échec du fetch depuis SVN."; exit 1; }


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


# a décommenter si on veut avoir un repo git complètement clean
# attention, cela rend le repo impossible a mettre a jour depuis svn
: <<'COMMENT'
#suppression des branches svn déjà migrées sous git
for ref in $(git for-each-ref --format='%(refname)' refs/remotes/origin/); do
    git update-ref -d "$ref" 
    echo "Référence distante supprimée : $ref" 
done
COMMENT

#------------------------


# push sur le git en écrasant tout ce qu'il y avait avant, pcq la référence c'est le svn
git push --force origin master
git push --force origin --all
git push origin --tags



echo "Script terminé."

end=$(date +%s)
duration=$((end - start))
echo "Temps d'exécution : $duration secondes"



