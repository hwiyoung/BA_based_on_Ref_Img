% Estimate the EOs & GPs
% Including computing distortion parameters(radial, tangential etc)
% Impyeong Lee
% 2008. 1. 12
% modified by Hwiyoung Kim, at 2017. 03. 30

% Initialize the workspace
clearvars
close all
clc

path_input = 'input\\';
path_output = 'output\\';

%% Store AT configuration
std_IP = 0.00597 * 0.1;     % 0.1px, for ref.
std_IP2 = 0.00124643 * 0.1; % 0.1px, for smart
std_GPS = 0.0001;           % 0.0001m, for ref.
std_INS = 0.0001*pi/180;    % 0.0001deg, for smart
std_GPS2 = 1;              % 10m, for ref.
std_INS2 = 1*pi/180;       % 10deg, for smart

px_size = 0.006;    % mm/px
no_smart = 1;

% Read the true IO
fid = fopen( strcat(path_input,'IO_t.txt'),'r');
IO = fscanf(fid, '%f');
fclose(fid);

% Read the smartphone IO
fid = fopen( strcat(path_input,'IO_smart.txt'),'r');
IO_smart = fscanf(fid, '%f');
fclose(fid);

% Read the image points
fid = fopen( strcat(path_input,'IP_m.txt'),'r');
IP = fscanf(fid, '%f', [4 inf] )';
fclose(fid);
no_IP = size(IP,1);

% Read initial approx. for EO
fid = fopen( strcat(path_input,'EO_i.txt'),'r');
EO_i = fscanf(fid, '%f', [7 inf] )';
fclose(fid);

% Read initial approx. for GP
fid = fopen( strcat(path_input,'GP_i.txt'),'r');
GP_i = fscanf(fid, '%f', [4 inf] )';
fclose(fid);

% Read directly measured EO
fid = fopen( strcat(path_input,'EO_m.txt'),'r');
EO_c = fscanf(fid, '%f', [7 inf] )';
fclose(fid);
no_EO_c = size(EO_c,1);

% Compute the no. images
id_IM = [];
for n = 1:size(EO_i,1)
    if length ( find( id_IM == EO_i(n,1) ) ) == 0
        id_IM = [id_IM; EO_i(n,1)];
    end
end
no_IM = size(id_IM,1);

% Compute the no. ground points
id_GP = [];
for n = 1:size(IP,1)
    if length ( find( id_GP == IP(n,2) ) ) == 0
        id_GP = [id_GP; IP(n,2)];
    end
end
id_GP = sort(id_GP);
no_GP = size(id_GP, 1);

% Compute no. images of each GP appearing
cnt_GP = zeros( no_GP, 1);
for n = 1:no_IP
    idx = find ( id_GP == IP(n,2) );
    cnt_GP(idx) = cnt_GP(idx) + 1;
end
id_GP_inc = id_GP ( find( cnt_GP > 1 ) );
id_GP_inc = sort(id_GP_inc);
id_GP_exc = id_GP ( find( cnt_GP <= 1 ) );
no_GP_inc = length(id_GP_inc);

% Select GP and IP for AT
m = 0;
for np = 1:no_IP
    if length(find(id_GP_exc==IP(np,2))) == 0
        % check if the point index is in the index of gp exclusive
        m = m + 1;
        IP_inc(m,:) = IP(np,:);
    end
end
no_IP_inc = size(IP_inc,1);

tic
%% Set the initial approximations
% Kt_e : initial approximations of the EO of the photos
Kt_e = zeros(no_IM*6,1);
for n = 1:no_IM
    id = find ( EO_i(:,1) == id_IM(n) );
    Kt_e(n*6-5:n*6,1) = EO_i(id,2:7)';
end

% Kt_g : initial approximations of the ground points
Kt_g = zeros(no_GP_inc*3,1);
for n = 1:no_GP_inc
    id = find ( GP_i(:,1) == id_GP_inc(n) );
    Kt_g(n*3-2:n*3,1) = GP_i(id,2:4)';
end

%% Perform AT
delta = 1e-6;
cnst_ws = 1;

for k = 1:100
    fprintf( 'Iteration %d\n', k );
    % Initialize the design matrix and observations
    Ae = zeros(no_IP_inc*2, no_IM*6);
    Ag = zeros(no_IP_inc*2, no_GP_inc*3);
    
    % The rotational matrix and its derivatives
    for ni = 1:no_IM
        R_e{ni} = Rot3D(Kt_e(ni*6-2:ni*6,1));
        [dRe_om{ni}, dRe_ph{ni}, dRe_kp{ni}] = dRot3D(Kt_e(ni*6-2:ni*6,1));
    end
    
    % Set the design matrix and observations
    for np = 1:no_IP_inc
        imi = find ( id_IM == IP_inc(np,1) );       % image index
        gpi = find ( id_GP_inc == IP_inc(np,2) );   % GP index
        
        GC = Kt_g(gpi*3-2:gpi*3,1) -  Kt_e(imi*6-5:imi*6-3,1);
        ND = R_e{imi} * GC;        
        P_nu = - ND(1:2,1) / ND(3);
        r = sqrt(P_nu(1)^2 + P_nu(2)^2);
        
        % ******************************************************
        % Distortion correction
        radial = 1 + IO(6)*r^2 + IO(7)*r^4 + IO(8)*r^6 + IO(9)*r^8;
        x_d = P_nu(1) * radial + (IO(11) * (r^2 + 2*P_nu(1)^2) + 2*IO(10)*P_nu(1)*P_nu(2)) * (1 + IO(12)*r^2 + IO(13)*r^4);
        y_d = P_nu(2) * radial + (IO(10) * (r^2 + 2*P_nu(2)^2) + 2*IO(11)*P_nu(1)*P_nu(2)) * (1 + IO(12)*r^2 + IO(13)*r^4);
        
        % For reference images
        F0(1) = IO(1) + (IO(3) + IO(4)) * x_d + IO(5) * y_d;
        F0(2) = IO(2) + IO(3) * y_d;
        
        % For smartphone images
        F0_smart = IO_smart(1:2) - IO_smart(3) / ND(3) * ND(1:2,1);
        % ******************************************************
        
        dND(:,1:3) = -R_e{imi};
        dND(:,4) = dRe_om{imi} * GC;
        dND(:,5) = dRe_ph{imi} * GC;
        dND(:,6) = dRe_kp{imi} * GC;
        dND(:,7:9) = R_e{imi};
        
        % check whether IP is in smartphone images
        % needed for modification
        if imi == 12
            Ae(2*np-1:2*np,imi*6-5:imi*6) = IO_smart(3) / ND(3)^2 * [-ND(3) 0 ND(1); 0 -ND(3) ND(2)] * dND(:,1:6);
            Ag(2*np-1:2*np,gpi*3-2:gpi*3) = IO_smart(3) / ND(3)^2 * [-ND(3) 0 ND(1); 0 -ND(3) ND(2)] * dND(:,7:9);
            yi(2*np-1:2*np,1) = IP_inc(np,3:4)' - F0_smart;
        else
            Ae(2*np-1:2*np,imi*6-5:imi*6) = IO(3) / ND(3)^2 * [-ND(3) 0 ND(1); 0 -ND(3) ND(2)] * dND(:,1:6);
            Ag(2*np-1:2*np,gpi*3-2:gpi*3) = IO(3) / ND(3)^2 * [-ND(3) 0 ND(1); 0 -ND(3) ND(2)] * dND(:,7:9);
            yi(2*np-1:2*np,1) = IP_inc(np,3:4)' - F0';
        end
    end
    dp_h(:,k) = yi;

    Ke = zeros( (no_IM-no_smart)*6, no_IM*6 );
    for ni = 1:(no_IM-no_smart)
        imi = find ( id_IM == EO_i(ni,1) );
        for nc = 1:6
            Ke((ni-1)*6+nc, (imi-1)*6+nc) = 1;
            ye((ni-1)*6+nc, 1) = EO_i(ni,nc+1) - Kt_e((imi-1)*6+nc,1);
        end
    end

    % ******************************************************
    % Set the weight matrix *** only on reference images ***
    % ******************************************************
    Pi = eye(no_IP_inc*2) / std_IP ^ 2;
    smartphone = find(IP_inc(:,1) == 12);       % the index of IP included in smartphone images
    Pi(smartphone(1)*2-1:end,smartphone(1)*2-1:end) = eye(size(smartphone,1)*2) / std_IP2 ^ 2;

    Pe = zeros((no_IM-no_smart)*6);
    for ni = 1:(no_IM-no_smart)
       Pe(ni*6-5:ni*6-3,ni*6-5:ni*6-3) = eye(3) * cnst_ws / std_GPS ^ 2;
       Pe(ni*6-2:ni*6,ni*6-2:ni*6) = eye(3) * cnst_ws / std_INS ^ 2;
    end
     
    % Set the normal matrix
    Nee = Ae' * Pi * Ae + Ke' * Pe * Ke;
    Neg = Ae' * Pi * Ag;
    Ngg = Ag' * Pi * Ag;
    Ce = Ae' * Pi * yi + Ke' * Pe * ye;
    Cg = Ag' * Pi * yi;
    
    iNgg = zeros(size(Ngg));
    for n = 1:size(Ngg,1)/3
        iNgg(n*3-2:n*3,n*3-2:n*3) = inv(Ngg(n*3-2:n*3,n*3-2:n*3));
    end

    Nr = ( Nee - Neg * iNgg * Neg' );
    kt_e = inv(Nr) * ( Ce - Neg * iNgg * Cg );
    kt_g = iNgg * (Cg - Neg' * kt_e);
    kt = [kt_e; kt_g];
    
    Kt_e = Kt_e + kt(1:no_IM*6,1);
    Kt_g = Kt_g + kt(no_IM*6+1:no_IM*6+no_GP_inc*3,1);
    
    if norm(kt) < delta
        break
    end
end

no_IT = k;

A = [Ae Ag; Ke zeros(size(Ke,1),size(Ag,2))];
y = [yi; ye];

P = zeros(length(Pi)+length(Pe));
P(1:length(Pi),1:length(Pi)) = Pi;
P(length(Pi)+1:length(Pi)+length(Pe),length(Pi)+1:length(Pi)+length(Pe)) = Pe;

N = A' * P * A;
iN = inv(N);
et =  y - A * kt;
vct = ( et' * P * et ) / (size(A,1)-rank(A));
dp_h(:,no_IT+1) = et(1:no_IP_inc*2,1);

Dkt = vct * iN;
Skt = sqrt(diag(Dkt));
Ckt = diag(1./Skt) * Dkt * diag(1./Skt);

% Estimated EO and GP
for n = 1:no_IM
    EO_e(n,:) = [n Kt_e(n*6-5:n*6,1)'];
end
for n = 1:no_GP_inc
    GP_e(n,:) = [id_GP_inc(n) Kt_g(n*3-2:n*3,1)'];
end
Time_Elapsed = toc

% Analyze the estimation process
for n = 1:no_IT+1
    ip_stat{n}(:,1) = comp_stat(dp_h(1:2:2*no_IP_inc,n));
    ip_stat{n}(:,2) = comp_stat(dp_h(2:2:2*no_IP_inc,n));
    ip_stat{n}(:,3) = comp_stat(dp_h(1:2*no_IP_inc,n));
end

%% Store the estimated EO
fid = fopen( strcat(path_output, 'EO_e.txt'), 'w');
fprintf(fid, '%d\t%11.3f\t%11.3f\t%11.3f\t%11.6f\t%11.6f\t%11.6f\r\n', EO_e' );
fclose(fid);

% Store the estimated GPs
fid = fopen( strcat(path_output, 'GP_e.txt'), 'w');
fprintf(fid, '%d\t%11.3f\t%11.3f\t%11.3f\r\n', GP_e' );
fclose(fid);

% Store the summary of estimation process
fid = fopen( strcat(path_output, 'Est_summary.txt'), 'w');
fprintf(fid, 'No. image points: %d\r\n', size(IP,1) );
fprintf(fid, 'No. images: %d\r\n', size(EO_i,1) );
fprintf(fid, 'No. ground points: %d\r\n', size(GP_i,1) );
fprintf(fid, 'Size of Ae matrix: %d x %d\r\n', size(Ae,1), size(Ae,2) );
fprintf(fid, 'Size of Ag matrix: %d x %d\r\n', size(Ag,1), size(Ag,2) );
fprintf(fid, 'Size of Ke matrix: %d x %d\r\n', size(Ke,1), size(Ke,2) );
fprintf(fid, 'Size of A matrix: %d x %d\r\n', size(A,1), size(A,2) );
fprintf(fid, 'Size of N matrix: %d x %d\r\n', size(N,1), size(N,2) );
fprintf(fid, 'Size of Nr matrix: %d x %d\r\n', size(Nr,1), size(Nr,2) );
fprintf(fid, 'Estimation time: %g\r\n', Time_Elapsed );
fprintf(fid, 'No. Iteration: %d\r\n', no_IT );
fprintf(fid, 'Threshold for Iteration: %g\r\n', delta );
fprintf(fid, 'Residuals\r\n' );
for n = 1:no_IT+1
    fprintf(fid, ' Step %2d\t%11s\t%11s\t%11s\r\n', n-1, 'IP_x', 'IP_y', 'IP_a' );
    fprintf(fid, '  Maximum:\t%11.4f\t%11.4f\t%11.4f\r\n', ip_stat{n}(1,1), ip_stat{n}(1,2), ip_stat{n}(1,3) );
    fprintf(fid, '  Minimum:\t%11.4f\t%11.4f\t%11.4f\r\n', ip_stat{n}(2,1), ip_stat{n}(2,2), ip_stat{n}(2,3) );
    fprintf(fid, '  Average:\t%11.4f\t%11.4f\t%11.4f\r\n', ip_stat{n}(3,1), ip_stat{n}(3,2), ip_stat{n}(3,3) );
    fprintf(fid, '  Std_dv.:\t%11.4f\t%11.4f\t%11.4f\r\n', ip_stat{n}(4,1), ip_stat{n}(4,2), ip_stat{n}(4,3) );
    fprintf(fid, '  RMS    :\t%11.4f\t%11.4f\t%11.4f\r\n', ip_stat{n}(5,1), ip_stat{n}(5,2), ip_stat{n}(5,3) );
end
fclose(fid);

%% Visualize the Design Matrix
figure
imshow(A~=0)
axis on
hold on
for nip = 1:no_IP_inc
    plot([0.5, no_IM*6+no_GP_inc*3+0.5], [nip*2+0.5 nip*2+0.5], 'r:');
end
h = plot([0.5, no_IM*6+no_GP_inc*3+0.5], [no_IP_inc*2+0.5 no_IP_inc*2+0.5], 'r-');
set ( h, 'LineWidth', 2);
for nec = 1:(no_EO_c-no_smart)
    plot([0.5, no_IM*6+no_GP_inc*3+0.5], [no_IP_inc*2+nec*6+0.5 no_IP_inc*2+nec*6+0.5], 'r:');
end
for ni = 0:no_IM
    plot([ni*6+0.5, ni*6+0.5], [0.5, no_IP_inc*2+(no_EO_c-no_smart)*6+0.5], 'r:');
end
h = plot([no_IM*6+0.5, no_IM*6+0.5], [0.5, no_IP_inc*2+(no_EO_c-no_smart)*6+0.5], 'r-');
set ( h, 'LineWidth', 2);
for ng = 0:no_GP_inc
    plot([no_IM*6+ng*3+0.5, no_IM*6+ng*3+0.5], [0.5, no_IP_inc*2+(no_EO_c-no_smart)*6+0.5], 'r:');
end
for ni = 1:no_IM
    Nlb{ni} = sprintf('%d', ni);
end
for ng = 1:2:no_GP_inc
    Nlb{ni+(ng+1)/2} = sprintf('%d', id_GP_inc(ng));
end
for nip = 1:2:no_IP_inc
    Y_lb{(nip+1)/2} = sprintf('%d', nip);
end
for nec = 1:(no_EO_c-no_smart)
    Y_lb{ceil(no_IP_inc/2)+nec} = sprintf('%d', nec);
end
set(gca, 'XTick', [3.5:6:no_IM*6 no_IM*6+2:6:no_IM*6+no_GP_inc*3]);
set(gca, 'XTickLabel', Nlb);
set(gca, 'XAxisLocation', 'top' );
set(gca, 'YTick', [1.5:4:no_IP_inc*2 no_IP_inc*2+3.5:6:no_IP_inc*2+no_IM*6]);
set(gca, 'YTickLabel', Y_lb);
hold off
title('Design Matrix');

%% Visualize the Normal Matrix
figure
imshow(N~=0)
axis on
hold on
for ni = 0:no_IM
    plot([ni*6+0.5, ni*6+0.5], [0.5, no_IM*6+no_GP_inc*3+0.5], 'r:');
    plot([0.5, no_IM*6+no_GP_inc*3+0.5], [ni*6+0.5, ni*6+0.5], 'r:');
end
h = plot([0.5, no_IM*6+no_GP_inc*3+0.5], [no_IM*6+0.5, no_IM*6+0.5], 'r-');
set ( h, 'LineWidth', 2);
h = plot([no_IM*6+0.5, no_IM*6+0.5], [0.5, no_IM*6+no_GP_inc*3+0.5], 'r-');
set ( h, 'LineWidth', 2);
for ng = 0:no_GP_inc
    plot([no_IM*6+ng*3+0.5, no_IM*6+ng*3+0.5], [0.5, no_IM*6+no_GP_inc*3+0.5], 'r:');
    plot([0.5, no_IM*6+no_GP_inc*3+0.5], [no_IM*6+ng*3+0.5, no_IM*6+ng*3+0.5], 'r:');
end
for ni = 1:no_IM
    Nlb{ni} = sprintf('%d', ni);
end
for ng = 1:2:no_GP_inc
    Nlb{ni+(ng+1)/2} = sprintf('%d', id_GP_inc(ng));
end
set(gca, 'XTick', [3.5:6:no_IM*6 no_IM*6+2:6:no_IM*6+no_GP_inc*3]);
set(gca, 'XTickLabel', Nlb);
set(gca, 'XAxisLocation', 'top' );
set(gca, 'YTick', [3.5:6:no_IM*6 no_IM*6+2:6:no_IM*6+no_GP_inc*3]);
set(gca, 'YTickLabel', Nlb);
hold off
title('Normal Matrix');

%% Visualize the structure of the Nr matrix
figure
Nrim = Nr ~= 0;
imshow(Nr)
hold on
for ni = 0:no_IM
    plot([ni*6+0.5, ni*6+0.5], [0.5, no_IM*6+no_GP_inc*3+0.5], 'r:');
    plot([0.5, no_IM*6+no_GP_inc*3+0.5], [ni*6+0.5, ni*6+0.5], 'r:');
end
for ni = 1:no_IM
    Nrlb{ni} = sprintf('%d', ni);
end
set(gca, 'XTick', [3.5:6:no_IM*6]);
set(gca, 'XTickLabel', Nrlb);
set(gca, 'XAxisLocation', 'top' );
set(gca, 'YTick', [3.5:6:no_IM*6]);
set(gca, 'YTickLabel', Nrlb);
axis on
title('Reduced Normal Matrix');

%% Visualize the Correlation Matrix
figure
imshow(abs(Ckt),[0 1])
axis on
hold on
for ni = 0:no_IM
    plot([ni*6+0.5, ni*6+0.5], [0.5, no_IM*6+no_GP_inc*3+0.5], 'r:');
    plot([0.5, no_IM*6+no_GP_inc*3+0.5], [ni*6+0.5, ni*6+0.5], 'r:');
end
h = plot([0.5, no_IM*6+no_GP_inc*3+0.5], [no_IM*6+0.5, no_IM*6+0.5], 'r-');
set ( h, 'LineWidth', 2);
h = plot([no_IM*6+0.5, no_IM*6+0.5], [0.5, no_IM*6+no_GP_inc*3+0.5], 'r-');
set ( h, 'LineWidth', 2);
for ng = 0:no_GP_inc
    plot([no_IM*6+ng*3+0.5, no_IM*6+ng*3+0.5], [0.5, no_IM*6+no_GP_inc*3+0.5], 'r:');
    plot([0.5, no_IM*6+no_GP_inc*3+0.5], [no_IM*6+ng*3+0.5, no_IM*6+ng*3+0.5], 'r:');
end
for ni = 1:no_IM
    Nlb{ni} = sprintf('%d', ni);
end
for ng = 1:2:no_GP_inc
    Nlb{ni+(ng+1)/2} = sprintf('%d', id_GP_inc(ng));
end
set(gca, 'XTick', [3.5:6:no_IM*6 no_IM*6+2:6:no_IM*6+no_GP_inc*3]);
set(gca, 'XTickLabel', Nlb);
set(gca, 'XAxisLocation', 'top' );
set(gca, 'YTick', [3.5:6:no_IM*6 no_IM*6+2:6:no_IM*6+no_GP_inc*3]);
set(gca, 'YTickLabel', Nlb);
axis on
colorbar
title('Correlation Matrix');

%% Visualize the image point difference before adjustment
figure
subplot(2,2,1);
axis on
bar(1:no_IP_inc, dp_h(1:2:no_IP_inc*2,1)*1e3, 0.5);
ylabel('\Delta x [um]');
xlabel('ID');
title('Residuals of Image Points (\Delta x)');

subplot(2,2,2);
axis on
bar(1:no_IP_inc, dp_h(2:2:no_IP_inc*2,1)*1e3, 0.5);
ylabel('\Delta y [um]');
xlabel('ID');
title('Residuals of Image Points (\Delta y)');

subplot(2,2,3);
axis on
hist(dp_h(1:2:no_IP_inc*2,1)*1e3, 99:1:99);
xlabel('\Delta x [um]');
ylabel('No. counts');
title('Histogram \Delta x');

subplot(2,2,4);
axis on
hist(dp_h(2:2:no_IP_inc*2,1)*1e3, 99:1:99);
xlabel('\Delta y [um]');
ylabel('No. counts');
title('Histogram of \Delta y');

%% Visualize the image point difference after adjustment
figure
subplot(2,2,1);
axis on
bar(1:no_IP_inc, dp_h(1:2:no_IP_inc*2,no_IT+1)*1e3, 0.5);
ylabel('\Delta x [um]');
xlabel('ID');
title('Residuals of Image Points (\Delta x)');

subplot(2,2,2);
axis on
bar(1:no_IP_inc, dp_h(2:2:no_IP_inc*2,no_IT+1)*1e3, 0.5);
ylabel('dy [um]');
xlabel('ID');
title('Residuals of Image Points (\Delta y)');

subplot(2,2,3);
axis on
hist(dp_h(1:2:no_IP_inc*2,no_IT+1)*1e3, 99:1:99);
xlabel('\Delta x [um]');
ylabel('No. counts');
title('Histogram \Delta x');

subplot(2,2,4);
axis on
hist(dp_h(2:2:no_IP_inc*2,no_IT+1)*1e3, 99:1:99);
xlabel('\Delta y [um]');
ylabel('No. counts');
title('Histogram \Delta y');


