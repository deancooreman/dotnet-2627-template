node {
    // Get the code from the repository.
    stage('Checkout') {
        checkout scm
    }
    // Build the image on the buildserver. The Dockerfile also runs the unit
    // tests, so a failing test stops the pipeline here, before the deploy.
    stage('Build & Test') {
        sh 'bash rise-app.sh build'
    }
    // Copy the image to the appserver and (re)start the container there. The
    // SSH key is the credential created by Ansible (Configuration as Code).
    stage('Deploy') {
        sshagent(credentials: ['appserver-deploy']) {
            sh 'bash rise-app.sh deploy'
        }
    }
}
