(function () {
  const F = window.BankFeatures;
  window.BankWorkspace.init({
    role: 'Admin', roleIcon: 'shield', roleSummary: 'Branch administration, workforce management and scheduled maintenance.', defaultSection: 'overview',
    nav: [
      { id:'overview', label:'Admin overview', shortLabel:'Home', icon:'dashboard', group:'Workspace', title:'Administrative command centre', description:'Track banking operations, staffing, branch activity and pending workload.' },
      { id:'customers', label:'Customers', shortLabel:'Customers', icon:'users', group:'Banking operations', title:'Customer management', description:'Search, register, update and deactivate customer records.' },
      { id:'accounts', label:'Accounts', shortLabel:'Accounts', icon:'card', group:'Banking operations', title:'Account administration', description:'Manage account lifecycle, restrictions, types and history.' },
      { id:'transactions', label:'Transactions', shortLabel:'Transactions', icon:'transfer', group:'Banking operations', title:'Transaction administration', description:'Create and supervise transactions, pending batches and reversals.' },
      { id:'loans', label:'Loans', shortLabel:'Loans', icon:'loan', group:'Banking operations', title:'Loan administration', description:'Create loans, collect installments and monitor overdue exposure.' },
      { id:'employees', label:'Employees', icon:'briefcase', group:'People & branches', title:'Employee administration', description:'Hire employees, create logins, change job titles, suspend or terminate.' },
      { id:'transfers', label:'Employee transfers', icon:'transfer', group:'People & branches', title:'Employee transfer workflow', description:'Submit manager requests and record current/destination manager decisions.' },
      { id:'branches', label:'Branches', icon:'branch', group:'People & branches', title:'Branch directory', description:'Review branch records and operational details.' },
      { id:'reports', label:'Admin reports', icon:'reports', group:'Insights & controls', title:'Administrative reports', description:'Read operational and administrative SQL Server reporting views.' },
      { id:'maintenance', label:'Maintenance', icon:'settings', group:'Insights & controls', title:'Scheduled maintenance controls', description:'Run pending transaction, overdue installment, dormant account and interest tasks.' },
      { id:'profile', label:'Profile & security', icon:'shield', group:'Account', title:'Profile and security', description:'Review your effective roles and active session.' }
    ],
    sections: { overview:F.sections.staffOverview, customers:F.sections.customers, accounts:F.sections.staffAccounts, transactions:F.sections.staffTransactions, loans:F.sections.staffLoans, employees:F.sections.employees, transfers:F.sections.transfers, branches:F.sections.branches, reports:F.sections.reports, maintenance:F.sections.maintenance, profile:F.sections.profile },
    actions: F.actions
  });
})();
