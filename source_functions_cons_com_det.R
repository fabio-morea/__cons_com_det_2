

# Author: Fabio Morea @ Area Science Park
# Acknowledgments: this research work is supervided by prof. Domenico De Stefano, within the frame of PhD in Applied Data Science and Artificial Intelligence @ University of Trieste

# Package: test consensus community detection algorith
 

## clear terminal
shell("cls")

## load libraries
library(tidyverse, warn.conflicts = FALSE)
library(igraph)
library(glue)
library(ggpubr)
library(RColorBrewer)
library(ggplot2)
library(NMI)
library(rjson)
library(jsonlite) 

print("loading Consensus Community Detection functions ...")

compare_clustering_results <- function(all_clusters, 
                                       min_p = 0.5, 	 	# proportion of membership to be assigned to community 0
                                       min_vids = 4, 		# number of vertices to be assigned to community 0
                                       min_w = 1/1000,	# fraction of whole network weight to be assigned to community 0
  echo = FALSE)
{ 
    
    # inspect and compare the clustering results
    # in this case compare all N trials and calculate the "proportion of membership"i.e. 
    # i.e. how many times each company is in the same cluster of any other company
    # Then select as a cluster only those who have a probability > threshold 50%	
    
    x <- matrix(0, nrow=nrow(all_clusters), ncol=nrow(all_clusters))
    colnames(x)<-V(g)$name
    rownames(x)<-V(g)$name
    
    for (i in (1:n_trials)){
        nclusters <- max(all_clusters[,i])
        for (k in 1:nclusters) {
            samecluster <- (which(all_clusters[,i]==k))
            nc <- length(samecluster)
            for (t in 1:nc){
                for (j in 1:nc){ 
                    x[samecluster[j],samecluster[t]] <- x[samecluster[j],samecluster[t]] +1
                }
            }
        }
    }
    
    remaining <- x/ncol(all_clusters) #normalize
    
    v.processed <- 0
    current.cluster = 0 	
    ccs <- data.frame(name = V(g)$name)
    ccs$mbshp = rep(0, nrow(ccs))
    ccs$prob = apply(remaining, 1, max)
    
    weights <- strength(g)
    min_weight <- min_w * sum(weights)  
     
    
    more_clusters_to_process = TRUE
    
    
    while (more_clusters_to_process){
        cluster_ii_members <- which(remaining[1, ] > min_p)
        v.processed <- v.processed + length(cluster_ii_members)
        if (echo==TRUE) {print(paste("start While loop with v to process = ", dim(remaining)[1], v.processed ))}
        selected <- remaining[cluster_ii_members, cluster_ii_members]
        if (is.matrix(selected)) {
            diag(selected) <- 0 # diagonal elements are not relevant
            enough_vids 	<- length(cluster_ii_members) > min_vids
            enough_weight 	<- sum(weights[cluster_ii_members]) > min_weight
            if ( enough_vids & enough_weight) { #############à TO DO add PRNING with minvids and minweght
                current.cluster <- current.cluster + 1
                if (echo==TRUE) {print(paste("community", current.cluster, max(selected),length(cluster_ii_members) , sum(weights[cluster_ii_members])))}
                
                for (j in 1:nrow(selected)) {
                    nn <- names(selected[1,])[j]
                    if (echo==TRUE)  {print(paste("Adding", nn, "to comm",current.cluster ))}
                    ccs$mbshp[ccs$name == nn] <-  current.cluster
                    ccs$prob[ccs$name == nn] <-  max(selected[j,])
                    
                }
            } else {
              if (echo==TRUE)  {print(paste("community zero", max(selected),length(cluster_ii_members) , sum(weights[cluster_ii_members])))}
                for (j in 1:nrow(selected)) {
                    nn <- names(selected[1,])[j]
                    ccs$mbshp[ccs$name == nn] <-  0
                    ccs$prob[ccs$name == nn] <-  max(selected)
                }
            }
        }
        tmp <- remaining[-cluster_ii_members, -cluster_ii_members]
        if (is.matrix(tmp)){
            if (dim(tmp)[1] < 1 ){
                more_clusters_to_process <- FALSE
            }
            remaining <- tmp
        } else {
            more_clusters_to_process <- FALSE
        } 
    }
    return(ccs)
}


consensus_community_detection <- function(g, alphas, reps, n_trials, epsilon, res, min_p, min_vds, min_w, echo = FALSE ) {
  
  
  dfresults <- tibble( rep = 0,
                       trial = 0,
                       a = 0.0,
                       r = 0.0,
                       method = "_",
                       modularit = 0.0,
                       nc = 0, 
                       membership = list(), #membership as community label 
                       rob_mem = list()     #robustness of membership 
              )%>% head(0)
  
  j <- 0
  
  

  
  
  for (alpha in alphas){
      print(paste("Alpha", alpha))
      for (rep in 1:reps){
          print(paste("Repetition", rep))
          
          all_clusters <- c()
          for (i in 1:n_trials){
              #print(paste("Trial", i))
              n_items <- length(E(g))
              n_null <- as.integer(alpha * n_items)
              applied_weights <- E(g)$ww 
              applied_weights[sample(n_items,n_null)] <- epsilon
              E(g)$weight <- applied_weights
              resol = as.numeric(sample(res, 1))
              cluster_tmp <- cluster_louvain(g, weights = applied_weights , resolution = resol)
              all_clusters <- cbind(all_clusters,cluster_tmp$membership)
              m <- modularity (g,  cluster_tmp$membership)	
              mbs <- list(cluster_tmp$membership)		
              
              j <- j + 1 
              dfresults[j,] <- list(
                  rep = rep,
                  trial = i,
                  a = alpha,
                  r = resol,
                  method = "LV",
                  modularit = m,
                  nc = max(cluster_tmp$membership), 
                  membership  = list(mbs),
                  rob_mem = list(rep(NA,0))       #robustness of membership 
              )			
          }
          
          ccs <- compare_clustering_results(all_clusters, 
          min_p = min_p, 	 # proportion of membership below which a node is assigned to community 0
          min_vids = min_vds, 		 # number of vertices below which a node is assigend to community 0
          min_w = min_w,
          echo = echo)
  
  # (community weight / total network weight) below which a node is assigned to community 0
          V(g)$comm_louvain <- 0
          V(g)$rob_mem <- 0
          
          # #sort cluster by decreasing size
          cl_conv_table = as.data.frame(table(ccs$mbshp)) %>%
              rename(comm_size = Freq) %>%
              rename(cccc=Var1) %>%
              arrange(-comm_size)
          
          
          
          # if echo {print("assigning sorted cluster labels...")}
          cl_new_labels <- 1
          for (clid in cl_conv_table$cccc){
              selected_vids <- ccs %>%
                  filter(mbshp == clid) %>%
                  select(name) %>%
                  pull() %>%
                  unlist()
              V(g)[ V(g)$name %in% selected_vids ]$comm_louvain <- cl_new_labels
              cl_new_labels <- cl_new_labels + 1
          }	
          
          V(g)$rob_mem <- ccs$prob

          
          j <- j + 1 
          dfresults[j,] <- list(
              rep = rep,
              trial = i,
              a = alpha,
              r = resol,
              method = "CONS",
              modularit = modularity(g, V(g)$comm_louvain + 1 ),
              nc = max(V(g)$comm_louvain + 1), 
              membership  = list(V(g)$comm_louvain),
              rob_mem = list(V(g)$rob_mem) 
          )	
      }
  }
  
  return(dfresults) 
} 




