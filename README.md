Setting up Kubernetes and Airflow the GitOps Way
=====

# AWS CLI

We'll use the AWS CLI tool to interact with resources in our AWS account.

## Install the AWS CLI

Use our system's package manager to install the `aws-cli` package. (On some distributions, this may be called `awscli`.)

After installation, test by opening a terminal window and typing the following command.

```
$ aws --version
```

We should see something similar to 

```
aws-cli/1.16.263 Python/3.7.4 Linux/4.19.84-1-MANJARO botocore/1.12.253
```
.

## Configure the AWS CLI profile

In AWS console, create an IAM user that we will use to deploy to AWS. **Do not use your root account.** Grant the user sufficient permissions &mdash; e.g., add it to the `AdministratorAccess` group.    

Create an IAM access key for the user, and store it in a safe place. Follow [the instructions](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html) to configure a profile for AWS CLI.

```
$ aws configure --profile <profile-name>
```

# Create a VPC

We'll need to create the VPC infrastructure for our Kubernetes cluster. Use [a nice template](https://docs.aws.amazon.com/codebuild/latest/userguide/cloudformation-vpc-template.html).

```
pushd ./vpc
bash ./deploy-vpc.sh
popd
```

# Create a Kubernetes Cluster

## Install `eksctl`

There are [some instructions](https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html).

<!-- In Arch linux, an [AUR package](https://aur.archlinux.org/packages/eksctl/) is available.  Download the package archive. Then `cd` into the package directory and run `makepkg -si`.

```
pushd ~/Downloads
git clone https://aur.archlinux.org/eksctl.git
cd eksctl
makepkg -si
# this will take a while
popd
``` -->

We might need to install a few packages along the way, such as `binutils` and `gcc`. This should also install `kubectl`, but we should verify that it is installed with the package manager. Also verify that `aws-iam-authenticator` is installed.  On Arch linux, there is an AUR package.

## Create asymmetric keypair

Unfortunately, AWS is limited to RSA keys; otherwise, we'd use the [more secure Ed52219 algorithm](https://wiki.archlinux.org/index.php/SSH_keys#Generating_an_SSH_key_pair).

```
ssh-keygen
```

## Create the cluster

Now let's create create the cluster.

```
pushd ./eksctl
bash deploy-cluster.sh
popd
```

# Configure GitOps

## Create a keypair for Kubernetes to access GitHub

Best practice is not to reuse the key that `eksctl`/`kubectl` uses to talk to the Kubernetes cluster, but to create a separate key. Fortunately, GitHub supports the more secure Ed25519 key.

```
ssh-keygen -t ed25519 -f ~/.ssh/kubernetes_github_ed25519
```

Add the **public** key to your GitHub profile settings.

## Create a GitHub repository

Create a repository to contain the manifests that define the Kubernetes cluster. Call it e.g. `kubernetes-gitops`. We can go ahead and clone this empty repo to our workstation.

```
pushd ~/code/repos
GIT_SSH_COMMAND='ssh -i ~/.ssh/kubernetes_github_ed25519' \
  git clone git@github.com:dustbort/kubernetes-gitops.git
popd
```

## Bind the GitHub repo to Kubernetes for GitOps

```
pushd ./eksctl
bash ./enable-repo.sh
popd
```

Now, take the key that was outputted to the terminal, and add it as a deployment key for the GitHub repository, with write access. Shortly, we will see that a commit has been made to the `flux` directory.

## Add a quick start profile to the Kubernetes cluster

We will use the enabled GitOps to quickly set up the cluster.

```
pushd ./eksctl
bash ./enable-profile.sh
popd
```

Again, we can check the gitops repo and see that a commit has been made to the `base` directory. After some time, we will see that the manifests have been applied to the cluster via gitops. Wait for everything to reach the `Running` state.

```
AWS_PROFILE=dustbort kubectl get all --all-namespaces
```

# Connect to the Kubernetes dashboard

The quick start includes the Kubernetes dashboard. To [authenticate with the dashboard](https://docs.aws.amazon.com/eks/latest/userguide/dashboard-tutorial.html), we will need to set up `eks-admin`. Pull the latest version of the gitops repo.  Then add the following file:

`eks-admin/eks-admin-service-account.yaml`:
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: eks-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: eks-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: eks-admin
  namespace: kube-system
```

Commit and push the repo. Flux will detect the changes and apply them to the cluster after a short while.

Then we can get a token to connect to the dashboard. (We will know that eks-admin has not been applied yet if the following command spits out a bunch of keys, instead of a single matching key.)

```
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')
```

We use `kubectl` to proxy a connection to the cluster.

```
AWS_PROFILE=dustbort kubectl proxy
```

Then navigate to [the dashboard](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login) and use the token to access.

# Install Airflow

Because there are many dependencies and configurations for Airflow on Kubernetes, we will use a standard helm chart.

[Install helm](https://helm.sh/docs/intro/install/).

Fetch the heml chart for Airflow and copy the values.

```
pushd ./helm
bash ./fetch.sh airflow
bash ./values.sh airflow
popd
```

Edit `./helm/values/airflow/values.yaml` and set the following values:

<table>
  <thead>
    <tr>
      <th>Property</th>
      <th>Value</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>airflow.image.repository</td>
      <td>datarods/docker-airflow</td>
    </tr>
    <tr>
      <td>airflow.image.tag</td>
      <td>1.10.4-2</td>
    </tr>
  </tbody>
</table>

After setting the values, we can render the manifest from the helm chart templates.

```
pushd ./helm
bash manifest.sh airflow airflow airflow
popd
```

Now we are ready to put the manifests into the Kubernetes gitops repo.

```
rm -rf ../kubernetes-gitops/airflow
cp -a ./helm/manifests/airflow ../kubernetes-gitops/airflow
```

Commit and push the repo. Soon, Airflow will be active in the cluster.

Once Airflow appears in the list of running services, we can connect to its web interface. First, forward a port on our computer to the port on which the `airflow-web` is running.

```
AWS_PROFILE=dustbort kubectl port-forward service/airflow-web 8080:8080 -n default
```

Now visit [http://localhost:8080](http://localhost:8080).

Right away, there is a bug in the configuration. From the menu, navigate to Admin &gt; Connections. Click the edit icon for the `airflow_db` connection.  Make the following settings:

<table>
  <thead>
    <tr>
      <th>Property</th>
      <th>Value</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Conn Type</td>
      <td>Postgres</td>
    </tr>
    <tr>
      <td>Host</td>
      <td>airflow-postgresql</td>
    </tr>
    <tr>
      <td>Login</td>
      <td>postgres</td>
    </tr>
    <tr>
      <td>Password</td>
      <td>airflow</td>
    </tr>
    <tr>
      <td>Port</td>
      <td>5432</td>
    </tr>
  </tbody>
</table>

Now, from the menu, navigate to Data Profiling &gt; Charts.  Then select the item *Airflow task instance by type*. If we don't see a database connection error, then the `airflow_db` connection is configured correctly.

# Configure GitOps for DAGs

## Create a keypair for Airflow to access GitHub

Best practice is not to reuse the key that `eksctl`/`kubectl` uses to talk to the Kubernetes cluster, but to create a separate key. Fortunately, GitHub supports the more secure Ed25519 key.

```
ssh-keygen -t ed25519 -f ~/.ssh/airflow_github_ed25519
```

Add the **public** key to your GitHub profile settings.

## Create a GitHub repository

Create a repository to contain the DAGs for Airflow. Call it e.g. `airflow-dags-gitops`. We can go ahead and clone this empty repo to our workstation.

```
pushd ~/code/repos
GIT_SSH_COMMAND='ssh -i ~/.ssh/airflow_github_ed25519' \
  git clone git@github.com:dustbort/airflow-dags-gitops.git
popd
```

## Bind the GitHub repo to Airflow for GitOps

Create a known hosts file for Airflow, containing the entry for `github.com`. We can copy this entry from our `known_hosts` file.

```
ssh-keyscan github.com > ~/.ssh/airflow_known_hosts
```

Create a Kubernetes secret that conforms to the format that Airflow git-sync requires.

```
AWS_PROFILE=dustbort \
kubectl create secret generic airflow-github-secrets \
  --from-file=id_ed25519=$HOME/.ssh/airflow_github_ed25519 \
  --from-file=id_id_ed25519=$HOME/.ssh/airflow_github_ed25519.pub \
  --from-file=known_hosts=$HOME/.ssh/airflow_known_hosts
```


Edit `./helm/values/airflow/values.yaml` and set the following values:

<table>
  <thead>
    <tr>
      <th>Property</th>
      <th>Value</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>dags.git.url</td>
      <td>git@github.com:dustbort/airflow-dags-gitops.git</td>
    </tr>
    <tr>
      <td>dags.git.secret</td>
      <td>airflow-github-secrets</td>
    </tr>
    <tr>
      <td>dags.initContainer.enabled</td>
      <td>true</td>
    </tr>
  </tbody>
</table>

After setting the values, we can render the manifest from the helm chart templates.

```
pushd ./helm
bash manifest.sh airflow airflow airflow
popd
```

Now we are ready to put the manifests into the Kubernetes gitops repo.

```
rm -rf ../kubernetes-gitops/airflow
cp -a ./helm/manifests/airflow ../kubernetes-gitops/airflow
```

Commit and push the repo. Soon, Airflow will be active in the cluster.

Once Airflow appears in the list of running services, we can connect to its web interface. First, forward a port on our computer to the port on which the `airflow-web` is running.

```
AWS_PROFILE=dustbort kubectl port-forward service/airflow-web 8080:8080 -n default
```

## Initialize the DAGs gitops repo

If the repo is totally empty, when Airflow tries to pull the DAGs, then the `master` branch will not exist, causing the gitops script to crash the pods. So, let's make an initial commit.  Our DAGs repo should be a proper python module, so we can at least add an empty `__init__.py` file. In addition, we might add a DAG just for testing. We can use one such as [this](https://github.com/apache/airflow/blob/master/airflow/example_dags/example_bash_operator.py).  Commit and push the repo. In Airflow web interface, from the menu, navigate to DAGs.  After a few minutes, when we refresh the page, we should see the DAGs that we pushed will appear in the list.  We can test by running the DAGs from the web interface.