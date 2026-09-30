function summaryTbl = summarizeDataset(data, targetVar, features)
%SUMMARIZEDATASET  Print column types, unique counts, and missingness.
%
%   Missingness is reported before any modelling decision. This function
%   does not impute or drop rows.

    vars = data.Properties.VariableNames;
    nObs = height(data);
    nVar = width(data);

    fprintf('\n================ DATASET SUMMARY ================\n\n');
    fprintf('Number of observations: %d\n', nObs);
    fprintf('Number of variables   : %d\n\n', nVar);
    fprintf('%-22s %-14s %14s %10s\n', 'Variable', 'Type', 'Unique Values', 'Missing');
    fprintf('%s\n', repmat('-', 1, 64));

    Type = strings(nVar, 1);
    UniqueValues = nan(nVar, 1);
    Missing = zeros(nVar, 1);
    Variable = string(vars(:));

    for i = 1:nVar
        col = data.(vars{i});
        Type(i) = string(class(col));
        Missing(i) = countMissing(col);
        if isnumeric(col) || islogical(col)
            if strcmp(vars{i}, targetVar)
                UniqueValues(i) = NaN;
                uniqStr = '-';
            else
                UniqueValues(i) = numel(unique(col(isfinite(double(col)))));
                uniqStr = sprintf('%d', UniqueValues(i));
            end
        else
            s = string(col);
            s(ismissing(s) | s == "" | s == "<undefined>") = missing;
            UniqueValues(i) = numel(unique(s(~ismissing(s))));
            uniqStr = sprintf('%d', UniqueValues(i));
        end
        fprintf('%-22s %-14s %14s %10d\n', vars{i}, Type(i), uniqStr, Missing(i));
    end
    fprintf('%s\n', repmat('-', 1, 64));

    if any(Missing > 0)
        fprintf('\nMissing values were detected:\n');
        for i = find(Missing > 0)'
            fprintf('  %s : %d missing (%.2f%%)\n', vars{i}, Missing(i), ...
                100 * Missing(i) / nObs);
        end
        fprintf(['Method that will be applied: listwise deletion of rows\n' ...
                 'with missing %s or missing feature labels.\n' ...
                 'No imputation. Outliers are NOT deleted.\n'], targetVar);
    else
        fprintf('\nNo missing values detected. No imputation or deletion applied.\n');
    end

    if ~ismember(targetVar, vars)
        error('summarizeDataset:NoTarget', 'Target variable "%s" was not found.', targetVar);
    end
    kar = data.(targetVar);
    fprintf('\nTarget "%s" class: %s   numeric: %s\n', targetVar, class(kar), ...
        yesno(isnumeric(kar) || islogical(kar)));

    fprintf('\nRequested categorical features and number of levels:\n');
    for i = 1:numel(features)
        f = features{i};
        if ~ismember(f, vars)
            fprintf('  %-18s  NOT FOUND in the table\n', f);
            continue;
        end
        s = string(data.(f));
        s(ismissing(s) | s == "" | s == "<undefined>") = missing;
        fprintf('  %-18s  %d levels\n', f, numel(unique(s(~ismissing(s)))));
    end

    summaryTbl = table(Variable, Type, UniqueValues, Missing);
end

function n = countMissing(col)
    if isnumeric(col) || islogical(col) || isdatetime(col) || isduration(col)
        n = sum(ismissing(col) | (isnumeric(col) & ~isfinite(double(col))));
    else
        s = string(col);
        n = sum(ismissing(s) | s == "" | s == "<undefined>" | ...
            strcmpi(s, "nan") | strcmpi(s, "nat"));
    end
end

function s = yesno(tf)
    if tf, s = 'YES'; else, s = 'NO'; end
end
