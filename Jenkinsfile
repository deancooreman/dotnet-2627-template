node {
    // Get the code from the repository.
    stage('Checkout') {
        checkout scm
    }
    // A new Jenkins has no previous build to compare with, so the first poll
    // always starts a build. Only record the current commit then (the checkout
    // above), so a fresh Jenkins doesn't start a heavy build by itself. Later
    // polls and builds started by hand run the whole pipeline.
    if (currentBuild.previousBuild == null &&
            currentBuild.getBuildCauses('hudson.triggers.SCMTrigger$SCMTriggerCause')) {
        echo 'First build started by polling: commit recorded, nothing built.'
        currentBuild.result = 'NOT_BUILT'
        return
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
