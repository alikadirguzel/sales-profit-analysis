function s = computeAnovaDecomposition(y, gidx)
%COMPUTEANOVADECOMPOSITION One-way ANOVA SS / MS / F decomposition.
%
%   F = MS_between / MS_within
%
%   Between-group SS captures how far group means sit from the grand mean.
%   Within-group SS captures residual variation around each group mean.
%
%   H0 (classical ANOVA): all group means of Profit are equal.
%   H1: at least one group mean differs.
%
%   gidx must be integer group codes 1..k with no empty groups.

    y = double(y(:));
    gidx = double(gidx(:));
    if numel(y) ~= numel(gidx)
        error('computeAnovaDecomposition:SizeMismatch', ...
            'y and group index must have the same length.');
    end

    n = numel(y);
    k = max(gidx);
    if k < 2
        error('computeAnovaDecomposition:TooFewGroups', ...
            'At least two groups are required for ANOVA.');
    end
    if n <= k
        error('computeAnovaDecomposition:TooFewObs', ...
            'Need more observations than groups.');
    end

    nG = accumarray(gidx, 1, [k, 1]);
    if any(nG < 1)
        error('computeAnovaDecomposition:EmptyGroup', ...
            'Empty groups are not allowed.');
    end

    grandMean = mean(y);
    sumG = accumarray(gidx, y, [k, 1]);
    meanG = sumG ./ nG;

    % SS_total = SS_between + SS_within
    ssTotal = sum((y - grandMean).^2);
    ssBetween = sum(nG .* (meanG - grandMean).^2);
    ssWithin = ssTotal - ssBetween;

    dfBetween = k - 1;
    dfWithin = n - k;
    dfTotal = n - 1;

    msBetween = ssBetween / dfBetween;
    msWithin = ssWithin / dfWithin;

    if msWithin <= 0
        F = Inf;
        pClassical = 0;
    else
        F = msBetween / msWithin;
        pClassical = fcdf(F, dfBetween, dfWithin, 'upper');
    end

    % Effect sizes (parametric ANOVA identity; reported even if assumptions fail)
    if ssTotal > 0
        etaSquared = ssBetween / ssTotal;
    else
        etaSquared = NaN;
    end
    omegaSquared = (ssBetween - dfBetween * msWithin) / (ssTotal + msWithin);

    s = struct();
    s.n = n;
    s.k = k;
    s.nG = nG;
    s.grandMean = grandMean;
    s.meanG = meanG;
    s.ssBetween = ssBetween;
    s.ssWithin = ssWithin;
    s.ssTotal = ssTotal;
    s.dfBetween = dfBetween;
    s.dfWithin = dfWithin;
    s.dfTotal = dfTotal;
    s.msBetween = msBetween;
    s.msWithin = msWithin;
    s.F = F;
    s.pClassical = pClassical;
    s.etaSquared = etaSquared;
    s.omegaSquared = omegaSquared;
end
