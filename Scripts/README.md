# Scripts Directory Organization

This directory contains all bash scripts organized by their purpose and scope.
## Directory Structure

```
Scripts/
├── README.md                          # This file
├── development/                       # Development environment scripts
│   ├── setup.sh                       # Project initialization
│   ├── start.sh                       # Start development environment
│   ├── stop.sh                        # Stop development environment
│   ├── install.sh                     # Install dependencies
│   ├── start_client.sh                # Start client application
│   ├── start_database.sh              # Start database
│   ├── start_microservices.sh         # Start microservices
│   ├── start_proxy.sh                 # Start proxy
│   ├── start_backend_environment.sh   # Start backend environment
│   ├── stop_client.sh                 # Stop client application
│   └── gen-grpc-web.sh                # Generate gRPC web client
├── deployment/                        # Deployment and CI/CD scripts
│   ├── deployment_utils.sh            # Deployment utility functions
│   ├── codedeploy/                    # AWS CodeDeploy scripts
│   │   ├── after-allow-traffic.sh
│   │   ├── after-install.sh
│   │   ├── application-start.sh
│   │   ├── before-allow-traffic.sh
│   │   ├── before-install.sh
│   │   ├── env.sh
│   │   ├── validate-service.sh
│   │   └── setup-codedeploy.sh
│   └── terraform/                     # Terraform deployment scripts
│       ├── install-docker-manager.sh  # Docker manager installation
│       ├── install-docker-worker.sh   # Docker worker installation
│       ├── setup-github-actions-codedeploy.sh
│       ├── setup-github-actions-oidc.sh
│       └── remove-github-actions-oidc.sh
├── create-service-github-action.sh    # Create github action for a new microservice
└── utils/                             # Shared utility scripts
    ├── common.sh                      # Common utility functions
    ├── print-utils.sh                 # Color variables and print functions
    ├── prompt.sh                      # User interaction functions
    └── validation.sh                  # Input validation utilities
    └── github-utils.sh                # GitHub utility functions
    └── aws-utils.sh                   # AWS utility functions
```