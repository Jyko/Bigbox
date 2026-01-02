# Fichier à ne pas modifier manuellement !
# Sauf si vous savez exactement ce que vous faites

# Autocomplétion pour kubectl, helm et kubectx
source <(kubectl completion bash)
source <(helm completion bash)
# Autocomplétion pour les alias
complete -o default -F __start_kubectl kubecolor
complete -o default -F __start_kubectl k
complete -o default -F __start_helm h
complete -o default -F _kube_contexts kc
complete -o default -F _kube_namespaces kn