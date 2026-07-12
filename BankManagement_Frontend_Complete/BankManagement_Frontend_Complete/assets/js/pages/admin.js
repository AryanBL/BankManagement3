(function () {
  const F = window.BankFeatures;
  window.BankWorkspace.init({
    role: 'Admin', roleIcon: 'shield', roleSummary: 'Current-branch administration plus separate personal banking access.', defaultSection: 'overview',
    nav: [
      { id:'overview', label:'Admin overview', shortLabel:'Home', icon:'dashboard', group:'Workspace', title:'Administrative command centre', description:'Track branch operations, staffing, account visibility and loan exposure.' },
      { id:'customers', label:'Customers', shortLabel:'Customers', icon:'users', group:'Branch operations', title:'Customer management', description:'View and manage only customers who own at least one account in your current branch.' },
      { id:'accounts', label:'Branch accounts', shortLabel:'Branch', icon:'card', group:'Branch operations', title:'Current branch accounts', description:'View and manage eligible accounts in your current branch. Financial transactions remain restricted to the account owner.' },
      { id:'loans', label:'Branch loans', shortLabel:'Loans', icon:'loan', group:'Branch operations', title:'Current branch loans', description:'Create and inspect loans and installment schedules for your current branch. Manually process overdue installments for this branch.' },
      { id:'my-accounts', label:'My accounts', shortLabel:'My accounts', icon:'wallet', group:'Personal banking', title:'My personal accounts', description:'Accounts owned by the CustomerID linked to your manager login.' },
      { id:'transactions', label:'My transactions', shortLabel:'Transfer', icon:'transfer', group:'Personal banking', title:'My transactions', description:'Create financial transactions only from your own accounts.' },
      { id:'my-loans', label:'My loans', shortLabel:'My loans', icon:'loan', group:'Personal banking', title:'My personal loans', description:'Review and pay only your own loan installments.' },
      { id:'employees', label:'Branch employees', icon:'briefcase', group:'People & branches', title:'Current branch employee administration', description:'View and manage eligible ordinary employees currently assigned to your branch. Other branches are not accessible.' },
      { id:'transfers', label:'Employee transfers', icon:'transfer', group:'People & branches', title:'Employee transfer workflow', description:'Submit manager requests and record current/destination manager decisions.' },
      { id:'branches', label:'Branches', icon:'branch', group:'People & branches', title:'Branch directory', description:'Review branch records and operational details.' },
      { id:'reports', label:'Admin reports', icon:'reports', group:'Insights & controls', title:'Administrative reports', description:'Read authorized reporting views. Branch-aware reports are scoped to your current branch.' },
      { id:'maintenance', label:'Maintenance', icon:'settings', group:'Insights & controls', title:'Scheduled maintenance controls', description:'Run pending transaction tasks and manually process overdue installments for your current branch.' },
      { id:'profile', label:'Profile & security', icon:'shield', group:'Account', title:'Profile and security', description:'Review your effective roles and active session.' }
    ],
    sections: {
      overview:F.sections.staffOverview,
      customers:F.sections.customers,
      accounts:F.sections.staffAccounts,
      loans:F.sections.staffLoans,
      'my-accounts':F.sections.staffOwnAccounts,
      transactions:F.sections.staffTransactions,
      'my-loans':F.sections.staffOwnLoans,
      employees:F.sections.employees,
      transfers:F.sections.transfers,
      branches:F.sections.branches,
      reports:F.sections.reports,
      maintenance:F.sections.maintenance,
      profile:F.sections.profile
    },
    actions: F.actions
  });
})();
