%% Categorical analysis of Profit
%
% Pipeline:
%   DATA -> VALIDATION -> DESCRIPTIVES -> DISTRIBUTIONS -> OUTLIERS
%   -> NORMALITY -> VARIANCE HOMOGENEITY -> CLASSICAL ANOVA -> EFFECT SIZE
%   -> PERMUTATION ANOVA -> KRUSKAL-WALLIS (robustness) -> POST-HOC
%   -> MULTIPLE TESTING -> FIGURES -> EXCEL
%
% To analyse additional categorical columns later, append names to `features`.
% Example: features{end+1} = 'Payment_Method';
%
% Reproducibility: rng(42). Outliers are detected but never auto-deleted.

clc; clear; close all;

try
    feature('DefaultCharacterSet', 'UTF-8');
catch
end

%% ---- central parameters ----
rng(42);
alpha            = 0.05;
nPermutations    = 10000;
confidenceLevel  = 0.95;
targetVar        = 'Profit';
resultsDir       = 'results';
figVisible       = 'off';   % 'on' if you want figure windows

features = {
    'City'
    'Region'
    'Product'
    'Category'
    'Sales_Channel'
    'Customer_Type'
};

opts = struct();
opts.alpha = alpha;
opts.nPermutations = nPermutations;
opts.confidenceLevel = confidenceLevel;
opts.targetVar = targetVar;

if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

reportPath = fullfile(resultsDir, 'command_window_report.txt');
fid = fopen(reportPath, 'w', 'n', 'UTF-8');
if fid < 0
    warning('Could not open %s for writing. Command Window only.', reportPath);
    fid = 1;
end

cleanup = onCleanup(@() closeReport(fid)); %#ok<NASGU>

logf(fid, 'MATLAB %s\n', version);
logf(fid, 'Random seed: rng(42)\n');
logf(fid, 'alpha = %.2f, nPermutations = %d, confidenceLevel = %.2f\n', ...
    alpha, nPermutations, confidenceLevel);

%% ---- load + inspect ----
[data, sourceFile] = loadAnalysisData();
logf(fid, 'Source file: %s\n', sourceFile);

summaryPreview = summarizeDataset(data, targetVar, features);
writetable(summaryPreview, fullfile(resultsDir, 'dataset_summary.xlsx'));

[data, notes] = validateAnalysisData(data, targetVar, features);
for i = 1:numel(notes)
    logf(fid, 'VALIDATION: %s\n', notes(i));
end

vars = data.Properties.VariableNames;
keep = {};
for i = 1:numel(features)
    if ismember(features{i}, vars)
        keep{end+1} = features{i}; %#ok<AGROW>
    else
        logf(fid, 'Skipping missing column: %s\n', features{i});
    end
end
features = keep;
if isempty(features)
    error('No requested categorical features were found in the table.');
end

yAll = double(data.(targetVar));

%% ---- per-feature analysis ----
nFeat = numel(features);
allR = cell(nFeat, 1);

for i = 1:nFeat
    feat = features{i};
    logf(fid, '\n>>> Analysing feature %d/%d: %s\n', i, nFeat, feat);

    g = data.(feat);
    R = analyzeCategoricalFeature(yAll, g, feat, opts);
    allR{i} = R;

    printFeatureReport(R, opts, fid);

    featDir = fullfile(resultsDir, feat);
    logf(fid, 'Saving figures to results/%s\n', feat);
    plotFeatureAnalysis(R, featDir, figVisible, targetVar);
end

%% ---- multiple testing, ranking, Excel ----
[summaryTbl, rankTbl] = exportAnalysisResults(allR, opts, resultsDir);
printGlobalSummary(allR, summaryTbl, rankTbl, opts, fid);

logf(fid, '\nFigures: results/<Feature>/*.png\n');
logf(fid, 'Text report: results/command_window_report.txt\n');
logf(fid, 'Done.\n');

%% ---- local helpers ----
function logf(fid, varargin)
    fprintf(varargin{:});
    if fid > 1
        fprintf(fid, varargin{:});
    end
end

function closeReport(fid)
    if fid > 1
        fclose(fid);
    end
end
