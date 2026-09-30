function [data, notes] = validateAnalysisData(data, targetVar, features)
%VALIDATEANALYSISDATA  Check Profit and categorical features before modelling.
%
%   Negative profit is allowed (loss-making orders). Inf/NaN in Profit are not.
%   Rows with invalid Profit are dropped (listwise) and the reason is recorded.
%   Outliers are not removed here.

    notes = strings(0, 1);
    vars = data.Properties.VariableNames;

    if ~ismember(targetVar, vars)
        error('validateAnalysisData:NoTarget', 'Column "%s" is missing.', targetVar);
    end

    y = data.(targetVar);
    if ~(isnumeric(y) || islogical(y))
        yNum = str2double(string(y));
        if all(isnan(yNum) & ~ismissing(string(y)))
            error('validateAnalysisData:NotNumeric', ...
                '"%s" is not numeric and could not be coerced.', targetVar);
        end
        notes(end+1) = sprintf('%s was coerced from %s to double.', targetVar, class(y)); %#ok<AGROW>
        y = yNum;
        data.(targetVar) = y;
    else
        data.(targetVar) = double(y);
        y = data.(targetVar);
    end

    badProfit = ismissing(y) | ~isfinite(y);
    nBad = sum(badProfit);
    if nBad > 0
        data = data(~badProfit, :);
        y = data.(targetVar);
        notes(end+1) = sprintf( ...
            'Removed %d rows with missing/non-finite %s (listwise).', nBad, targetVar); %#ok<AGROW>
    end

    nNeg = sum(y < 0);
    notes(end+1) = sprintf( ...
        'Negative %s values: %d (%.2f%%). These are kept (losses are valid).', ...
        targetVar, nNeg, 100 * nNeg / numel(y));

    present = {};
    for i = 1:numel(features)
        f = features{i};
        if ~ismember(f, data.Properties.VariableNames)
            notes(end+1) = sprintf('Feature "%s" is not in the table and will be skipped.', f); %#ok<AGROW>
            continue;
        end
        present{end+1} = f; %#ok<AGROW>
        s = string(data.(f));
        emptyMask = ismissing(s) | s == "" | s == "<undefined>";
        nEmpty = sum(emptyMask);
        if nEmpty > 0
            notes(end+1) = sprintf( ...
                'Feature %s has %d empty labels; those rows will be dropped only in that feature''s analysis.', ...
                f, nEmpty); %#ok<AGROW>
        end
        sClean = s(~emptyMask);
        nLev = numel(unique(sClean));
        if nLev < 2
            notes(end+1) = sprintf( ...
                'Feature %s has %d usable level(s); ANOVA requires >= 2.', f, nLev); %#ok<AGROW>
        end
        counts = countcats(removecats(categorical(sClean)));
        if any(counts < 5)
            small = sum(counts < 5);
            notes(end+1) = sprintf( ...
                'WARNING: %s has %d group(s) with n < 5. Tests for those groups are unreliable.', ...
                f, small); %#ok<AGROW>
        end
    end

    fprintf('\n================ DATA VALIDATION ================\n');
    for i = 1:numel(notes)
        fprintf('  - %s\n', notes(i));
    end
    fprintf('Usable features: %s\n', strjoin(present, ', '));
    fprintf('N after Profit validation: %d\n', height(data));
end
