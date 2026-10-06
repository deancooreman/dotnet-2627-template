node {
    // Get the code from the repository.
    stage('Checkout') {
        checkout scm
    }
    // Remove the container of the previous deployment.
    stage('Preparation') {
        catchError(buildResult: 'SUCCESS') {
            sh 'docker stop riserunning'   // stop the running container
            sh 'docker rm riserunning'     // delete it, so the name is free again
        }
    }
    // Build the image (this also runs the tests) and start the container.
    stage('Build & Test') {
        sh 'bash rise-app.sh'
    }
}
