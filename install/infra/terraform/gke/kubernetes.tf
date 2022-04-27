resource "google_compute_network" "vpc" {
  name                    = "${var.project_id}-vpc"
  auto_create_subnetworks = "false"
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = var.name
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.255.0.0/16"

  secondary_ip_range {
    range_name    = "cluster-secondary-ip-range"
    ip_cidr_range = "10.0.0.0/12"
  }

  secondary_ip_range {
    range_name    = "services-secondary-ip-range"
    ip_cidr_range = "10.64.0.0/12"
  }
}

resource "google_container_cluster" "gitpod-cluster" {
  name     = "${var.project_id}-gke"
  location = var.region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1
  release_channel {
    channel = "UNSPECIFIED"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "cluster-secondary-ip-range"
    services_secondary_range_name = "services-secondary-ip-range"
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }


    # only available in beta
    # dns_cache_config {
    #   enabled = true
    # }
  }

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name


}

resource "google_container_node_pool" "services" {
  name       = "${var.name}-services"
  location   = var.region
  cluster    = google_container_cluster.gitpod-cluster.name
  version    = var.kubernetes_version // kubernetes version
  initial_node_count = 1
  max_pods_per_node = 110

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/ndev.clouddns.readwrite",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]

    labels = {
      "gitpod.io/workload_meta" =true
      "gitpod.io/workload_ide" = true
    }

    preemptible  = var.pre-emptible
    image_type = "UBUNTU_CONTAINERD"
    disk_type = "pd-ssd"
    disk_size_gb  = var.disk_size_gb
    machine_type = var.machine_type
    tags         = ["gke-node", "${var.project_id}-gke"]
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  autoscaling {
    min_node_count = var.min_count
    max_node_count = var.max_count
  }


  management {
    auto_repair = true
    auto_upgrade = false
  }
}

resource "google_container_node_pool" "workspaces" {
  name       = "${var.name}-workspaces"
  location   = var.region
  cluster    = google_container_cluster.gitpod-cluster.name
  version    = var.kubernetes_version // kubernetes version
  initial_node_count = 1
  max_pods_per_node = 110

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/ndev.clouddns.readwrite",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]

    labels = {
      "gitpod.io/workload_metal" =true
      "gitpod.io/workload_ide" = true
      "gitpod.io/workload_workspace_services" = true
      "gitpod.io/workload_workspace_regular" = true
      "gitpod.io/workload_workspace_headless" = true
    }

    preemptible  = var.pre-emptible
    image_type = "UBUNTU_CONTAINERD"
    disk_type = "pd-ssd"
    disk_size_gb  = var.disk_size_gb
    machine_type = var.machine_type
    tags         = ["gke-node", "${var.project_id}-gke"]
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  autoscaling {
    min_node_count = var.min_count
    max_node_count = var.max_count
  }

  management {
    auto_repair = true
    auto_upgrade = false
  }
}

module "gke_auth" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/auth"

  project_id   = var.project_id
  location     = google_container_cluster.gitpod-cluster.location
  cluster_name = var.name
}
