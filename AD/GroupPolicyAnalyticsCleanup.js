const { Client } = require("@microsoft/microsoft-graph-client");
require("isomorphic-fetch");
const readline = require("readline");
const msal = require("@azure/msal-node");

// Authentication configuration
const msalConfig = {
    auth: {
        clientId: "<<Application ID>>",
        clientSecret: "<<Value from Client Secret>>",
        authority: "https://login.microsoftonline.com/<<Tenant ID>>"
    }
};

const tokenRequest = {
    scopes: ["https://graph.microsoft.com/.default"]
};

async function getAuthenticatedClient() {
    const cca = new msal.ConfidentialClientApplication(msalConfig);
    try {
        const authResult = await cca.acquireTokenByClientCredential(tokenRequest);
        console.log("Access Token:", authResult.accessToken);
        const client = Client.init({
            authProvider: (done) => {
                done(null, authResult.accessToken);
            }
        });
        return client;
    } catch (error) {
        console.error("Authentication error:", error);
        throw error;
    }
}

async function getReports(client) {
    try {
        const reports = await client
            .api("/deviceManagement/groupPolicyMigrationReports")
            .version("beta")  // Specifying the beta version
            .get();
        return reports.value;
    } catch (error) {
        console.error("Error fetching reports:", error);
        return [];
    }
}

async function deleteReport(client, reportId) {
    try {
        await client
            .api(`/deviceManagement/groupPolicyMigrationReports/${reportId}`)
            .version("beta")  // Specifying the beta version for deletion as well
            .delete();
        console.log(`Successfully deleted report with ID: ${reportId}`);
    } catch (error) {
        console.error(`Failed to delete report with ID: ${reportId} - ${error}`);
    }
}

async function selectReports(reports) {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
    });

    console.log("Available reports:");
    reports.forEach((report, index) => {
        console.log(`${index + 1}. ${report.displayName || report.id}`);
    });

    const answer = await new Promise((resolve) => {
        rl.question(
            "Enter the numbers of the reports you want to delete (comma-separated): ",
            resolve
        );
    });

    rl.close();

    const selectedIndexes = answer.split(",").map((n) => parseInt(n.trim()) - 1);
    return selectedIndexes.map((index) => reports[index]).filter(Boolean);
}

async function main() {
    try {
        const client = await getAuthenticatedClient();
        const reports = await getReports(client);

        if (reports.length === 0) {
            console.log("No reports found.");
            return;
        }

        const selectedReports = await selectReports(reports);

        for (const report of selectedReports) {
            await deleteReport(client, report.id);
        }
    } catch (error) {
        console.error("An error occurred:", error);
    }
}

main();
